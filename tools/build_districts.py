"""Kreise (die Ebene unter den Regionen) für die Detailansicht beim Hineinzoomen.

Pro Land wird die Ebene gewählt, die im Schnitt etwa 4 bis 70 Kreise pro Region ergibt, mit
Vorliebe für etwa 8 pro Region:
  - die Admin-1-Einheiten von Natural Earth, wenn sie für die Regionen gebündelt wurden
    (Frankreich: Départements, Italien: Provinzen, Japan: Präfekturen)
  - sonst geoBoundaries ADM2 oder ADM3 (Deutschland: Landkreise, USA: Counties, Schweiz: Bezirke)

Jeder Kreis wird auf seine Region zugeschnitten (Lücken gehen an den Nachbarn), und die Kreise einer
Region werden vereinfacht, ohne die Außenkante zu verändern. So decken sie ihre Region genau ab, und
am Landesrand liegt ihre Grenze auf derselben Linie wie das Nachbarland.

Ausgabe: ein komprimiertes JSON pro Land (Districts/DE.json.z ...), damit die App nur das gerade gezeigte Land
lädt, plus Districts/_sources.json mit Quelle und Lizenz je Land für die Lizenzseite.
Die geoBoundaries-Dateien werden beim ersten Lauf nach tools/raw/geoboundaries/ geladen.
"""
import collections
import json
import math
import pathlib
import subprocess
import zlib

import shapely
import shapely.affinity
from shapely.geometry import Point, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

from coverage import fit_to_outline, simplify_coverage

PER_REGION_MIN, PER_REGION_MAX, PER_REGION_TARGET = 2.5, 70, 8
# Vereinfachung je Region: unter einem Bildschirmpunkt, wenn die Region den Bildschirm füllt.
SIMPLIFY_PER_DEGREE_WIDTH = 1 / 450
SIMPLIFY_MIN, SIMPLIFY_MAX = 0.001, 0.03
NEAREST_MAX_DEG = 0.05
# Quellen mit weniger Eckpunkten pro Kreis im Schnitt gelten als zu grob.
MIN_MEAN_VERTICES = 150
API = "https://www.geoboundaries.org/api/current/gbOpen/ALL/{level}/"
# geoBoundaries nutzt für Kosovo einen eigenen Code.
ISO3_EXTRA = {"XKX": "XK"}


def deflate(text: str) -> bytes:
    """Rohes Deflate (ohne zlib-Kopf), wie es `NSData.decompressed(using: .zlib)` erwartet."""
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress(text.encode("utf-8")) + compressor.flush()


# Großstädte, deren Kreise zu einer Zone zusammengefasst werden (wie die Vororte bei den Städten).
BIG_CITY_MIN_POPULATION = 1_000_000
BIG_CITY_KM_PER_SQRT_THOUSAND = 0.19
BIG_CITY_RADIUS_MIN_KM, BIG_CITY_RADIUS_MAX_KM = 8.0, 40.0
# Zum Zusammenfassen gilt ein etwas größerer Umkreis als für die Vororte, damit auch die
# äußeren Bezirke dazugehören (Havering, Hillingdon in London).
BIG_CITY_MERGE_FACTOR = 1.5


def _big_cities(raw: pathlib.Path, codes: set[str]) -> dict[str, list[dict]]:
    cities = collections.defaultdict(list)
    with open(raw / "cities15000.txt", encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            population = int(c[14] or 0)
            if population < BIG_CITY_MIN_POPULATION or c[8] not in codes or c[7] == "PPLX":
                continue
            radius = BIG_CITY_MERGE_FACTOR * BIG_CITY_KM_PER_SQRT_THOUSAND * math.sqrt(population / 1000)
            cities[c[8]].append({"id": c[0], "name": c[1], "lat": float(c[4]), "lon": float(c[5]),
                                 "radius_km": min(max(radius, BIG_CITY_RADIUS_MIN_KM), BIG_CITY_RADIUS_MAX_KM)})
    for entries in cities.values():
        entries.sort(key=lambda e: -e["radius_km"])
    return cities


def _download(url: str, target: pathlib.Path) -> None:
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["curl", "-sfL", "-o", str(target), url], check=True)


class Districts:
    def __init__(self, raw_dir: pathlib.Path, regions, iso3_to_code: dict[str, str]):
        self.raw = raw_dir
        self.regions = regions
        self.iso3_to_code = {**iso3_to_code, **ISO3_EXTRA}
        self.by_country: dict[str, list[dict]] = {}
        self.sources: list[dict] = []
        self.levels: dict[str, str] = {}
        self._trees: dict[str, STRtree] = {}
        self.big_cities = _big_cities(raw_dir, set(iso3_to_code.values()))

        catalog = self._catalog()
        for code in sorted(regions.units_by_country):
            region_count = sum(r["cc"] == code for r in regions.regions)
            if region_count < 2:
                continue
            choice = self._choose(code, region_count, catalog.get(code, {}))
            if choice:
                self._build(code, *choice)
        for code, districts in self.by_country.items():
            self._trees[code] = STRtree([d["geometry"] for d in districts])

    def _catalog(self) -> dict[str, dict[str, dict]]:
        """geoBoundaries-Metadaten: pro Land und Ebene Anzahl, Lizenz und Download."""
        catalog = collections.defaultdict(dict)
        for level in ("ADM2", "ADM3"):
            path = self.raw / "geoboundaries" / f"_catalog_{level}.json"
            _download(API.format(level=level), path)
            for entry in json.loads(path.read_text()):
                code = self.iso3_to_code.get(entry["boundaryISO"])
                if code:
                    catalog[code][level] = entry
        return catalog

    def _choose(self, code: str, region_count: int, gb: dict[str, dict]):
        candidates = []
        units = self.regions.units_by_country.get(code, [])
        if self.regions.levels.get(code, "").split()[0] != "units":
            candidates.append(("natural-earth", len(units), None))
        for level, entry in gb.items():
            candidates.append((level, int(entry["admUnitCount"]), entry))

        def score(candidate):
            per_region = candidate[1] / region_count
            penalty = 0.0
            # Sehr grobe Quellen (etwa die britischen Bezirke bei geoBoundaries mit ~13 Eckpunkten)
            # verlieren gegen eine detailliertere Alternative.
            if candidate[2] is not None and float(candidate[2].get("meanVertices") or 0) < MIN_MEAN_VERTICES:
                penalty = 2.0
            return abs(math.log(per_region / PER_REGION_TARGET)) + penalty

        valid = [c for c in candidates if PER_REGION_MIN <= c[1] / region_count <= PER_REGION_MAX]
        return min(valid, key=score) if valid else None

    def _build(self, code: str, level: str, count: int, entry: dict | None) -> None:
        if level == "natural-earth":
            features = [(u["properties"]["adm1_code"], u["properties"].get("name_de") or u["properties"]["name"],
                         shape(u["geometry"]).buffer(0)) for u in self.regions.units_by_country[code]]
            self.sources.append({"cc": code, "source": "Natural Earth", "license": "Public Domain"})
        else:
            path = self.raw / "geoboundaries" / f"{entry['boundaryISO']}_{level}.geojson"
            _download(entry["simplifiedGeometryGeoJSON"], path)
            data = json.loads(path.read_text())
            features = [(f["properties"].get("shapeID") or str(i), f["properties"].get("shapeName") or "",
                         shape(f["geometry"]).buffer(0)) for i, f in enumerate(data["features"]) if f["geometry"]]
            self.sources.append({"cc": code, "source": f"geoBoundaries ({entry['boundarySource']})",
                                 "license": entry["boundaryLicense"]})
        self.levels[code] = f"{level} ({count})"

        # Erst jeder Kreis seiner Region zuordnen, dann pro Region vereinfachen: Die Toleranz
        # richtet sich nach der Region, damit kleine Regionen wie Greater London fein bleiben.
        by_region = collections.defaultdict(list)
        for key, name, geometry in features:
            anchor = geometry.representative_point()
            region = self.regions.region_id(code, anchor.y, anchor.x) or ""
            by_region[region].append((key, name, geometry))
        self._merge_big_cities(code, by_region)

        region_shapes = {r["id"]: r["geometry"] for r in self.regions.regions if r["cc"] == code}
        districts = []
        for region, members in by_region.items():
            # Kreise ohne Region liegen außerhalb des Landesumrisses der App.
            if region not in region_shapes:
                continue
            geometries = fit_to_outline([g for _, _, g in members], region_shapes[region])
            min_x, _, max_x, _ = shapely.total_bounds(geometries)
            tolerance = min(max((max_x - min_x) * SIMPLIFY_PER_DEGREE_WIDTH, SIMPLIFY_MIN), SIMPLIFY_MAX)
            for (key, name, _), geometry in zip(members, simplify_coverage(geometries, tolerance)):
                if not geometry.is_empty:
                    districts.append({"id": f"{code}:{key}", "region": region, "name": name, "geometry": geometry})
        self.by_country[code] = districts

    def _merge_big_cities(self, code: str, by_region: dict) -> None:
        """Großstädte ohne Unterteilung: Kreise, die zu einer Großstadt gehören (etwa die 33
        Londoner Bezirke), werden zu einer Zone mit dem Namen der Stadt zusammengefasst.

        Ein Kreis gehört zur Stadt, wenn er in derselben Region liegt, sein Mittelpunkt im Umkreis
        der Stadt liegt und er nicht größer als dieser Umkreis ist (sonst wäre es ein Landkreis
        mit viel Umland).
        """
        for city in self.big_cities.get(code, []):
            radius_deg = city["radius_km"] / 110.574
            circle = shapely.affinity.scale(Point(city["lon"], city["lat"]).buffer(radius_deg, 32),
                                            xfact=1 / math.cos(math.radians(city["lat"])), yfact=1.0)
            # Region der Stadt: die, in der die meiste Stadtfläche liegt (die Stadtmitte allein
            # kann an einer vereinfachten Grenze danebenliegen, etwa Lower Manhattan).
            candidates = {region: [m for m in members
                                   if circle.contains(m[2].representative_point()) and m[2].area <= circle.area]
                          for region, members in by_region.items()}
            center = Point(city["lon"], city["lat"])
            center_region = next((r for r, members in by_region.items()
                                  if any(m[2].buffer(0.01).contains(center) for m in members)), None)
            region = center_region if candidates.get(center_region) else \
                max(candidates, key=lambda r: sum(m[2].area for m in candidates[r]), default=None)
            belongs = candidates.get(region, []) if region is not None else []
            # Die Stadtmitte muss in einem der Kreise liegen, sonst gehören sie zu einer anderen
            # Stadt (Brooklyn ist bei GeoNames eigenständig, gehört aber zu New York).
            if len(belongs) < 2 or not any(m[2].buffer(0.01).contains(center) for m in belongs):
                continue
            merged = unary_union([m[2] for m in belongs]).buffer(0)
            keep = [m for m in by_region[region] if m not in belongs]
            by_region[region] = keep + [(f"city{city['id']}", city["name"], merged)]

    def district_id(self, cc: str, lat: float, lon: float) -> str | None:
        tree = self._trees.get(cc)
        if tree is None:
            return None
        districts = self.by_country[cc]
        point = Point(lon, lat)
        for index in tree.query(point, predicate="intersects"):
            return districts[index]["id"]
        index = tree.query_nearest(point, max_distance=NEAREST_MAX_DEG)
        return districts[index[0]]["id"] if len(index) else None

    def write(self, directory: pathlib.Path) -> int:
        directory.mkdir(parents=True, exist_ok=True)
        for old in [*directory.glob("*.json"), *directory.glob("*.json.z")]:
            old.unlink()
        total = 0
        for code, districts in self.by_country.items():
            out = []
            for district in districts:
                polygons = [g for g in shapely.get_parts(district["geometry"]) if g.geom_type == "Polygon"]
                # Gleiche Genauigkeit wie die Regionen, sonst klaffen an gemeinsamen Kanten feine Risse.
                rings = [[[round(v, 4) for xy in ring.coords for v in xy] for ring in [p.exterior, *p.interiors]]
                         for p in polygons if not p.is_empty]
                if rings:
                    out.append({"id": district["id"], "region": district["region"],
                                "name": district["name"], "polygons": rings})
            path = directory / f"{code}.json.z"
            path.write_bytes(deflate(json.dumps({"districts": out}, separators=(",", ":"), ensure_ascii=False)))
            total += path.stat().st_size
        (directory / "_sources.json").write_text(json.dumps(sorted(self.sources, key=lambda s: s["cc"]),
                                                            ensure_ascii=False, indent=0))
        return total
