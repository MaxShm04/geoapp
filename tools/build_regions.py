"""Regionen (Bundesländer, Staaten, Provinzen) aus Natural Earth Admin-1 für die Länderansicht.

Pro Land wird die Ebene gewählt, deren Zahl am besten zu 5 bis 30 Flächen passt: die Admin-1-
Einheiten selbst (Deutschland: 16 Bundesländer, USA: 51 Staaten) oder ihre Bündelung durch Natural
Earth in den Feldern `region`/`region_sub` (Frankreich: Regionen statt 101 Départements,
Großbritannien: 16 statt 232 Einheiten). Kleine Länder bekommen keine Regionen.

Die Flächen einer Gruppe werden vereinigt, auf den Länderumriss aus countries.json zugeschnitten
(Lücken gehen an den Nachbarn, siehe `fit_to_outline`) und alle Regionen eines Landes gemeinsam
vereinfacht, ohne die Außenkante zu verändern. So decken die Regionen ihr Land genau ab und enden
an derselben Linie wie das Nachbarland.
Braucht shapely (siehe tools/requirements.txt).
"""
import collections
import json
import math
import pathlib

import shapely
from shapely.geometry import Point, shape
from shapely.strtree import STRtree

from build_districts import deflate
from coverage import fit_to_outline, simplify_coverage

GROUPS_MIN, GROUPS_MAX = 5, 35
# Länder, für die eine feste Ebene besser passt als die automatische Wahl.
#   US: Bundesstaaten statt der 9 Zensus-Regionen
#   GB: Englands 9 Regionen, dazu Schottland, Wales und Nordirland als Ganzes
LEVEL_OVERRIDES = {
    "US": ("units", lambda p: p["adm1_code"]),
    "GB": ("nations", lambda p: p["region"] if p["geonunit"] == "England" else p["geonunit"]),
}
# Kleine Länder bekommen keine Regionen, dort reichen die Städtepunkte (Malta, Luxemburg, Hongkong).
MIN_COUNTRY_AREA_SQKM = 10_000
# Ohne Unterteilung oder ohne Reisende.
SKIP_COUNTRIES = {"AQ"}
# Vereinfachung je nach Landesgröße: etwa ein halber Bildschirmpunkt in der Länderansicht,
# also grob bei Kanada, fein bei Belgien. Werte in Grad.
SIMPLIFY_PER_DEGREE_WIDTH = 1 / 600
SIMPLIFY_MIN, SIMPLIFY_MAX = 0.004, 0.08
# Liegt eine Stadt durch die Vereinfachung knapp außerhalb aller Regionen, zählt die nächste
# Region ihres Landes innerhalb dieser Entfernung (in Grad, ~10 km).
NEAREST_MAX_DEG = 0.1
def _fit(count: int) -> float:
    """Wie gut eine Anzahl Regionen passt: 0 im Zielbereich, sonst der Abstand dazu."""
    if GROUPS_MIN <= count <= GROUPS_MAX:
        return -count / 1000  # im Bereich die feinere Ebene bevorzugen
    return GROUPS_MIN - count if count < GROUPS_MIN else count - GROUPS_MAX


def _area_sqkm(geometries: list) -> float:
    """Ungefähre Fläche: Quadratgrad, umgerechnet mit dem Breitengrad der Mitte."""
    total = 0.0
    for geometry in geometries:
        lat = geometry.centroid.y
        total += geometry.area * 110.574 * 111.320 * math.cos(math.radians(lat))
    return total


class Regions:
    def __init__(self, raw_dir: pathlib.Path, adm0_to_code: dict[str, str], outlines: dict):
        """`outlines`: Länderumrisse aus countries.json, wie die App sie zeichnet."""
        self.outlines = outlines
        data = json.loads((raw_dir / "ne_10m_admin_1_states_provinces.geojson").read_text())
        units_by_country = collections.defaultdict(list)
        for feature in data["features"]:
            props = feature["properties"]
            code = adm0_to_code.get(props["adm0_a3"])
            if code and feature["geometry"]:
                units_by_country[code].append(feature)

        self.units_by_country = units_by_country
        # Region: id, Ländercode, Name, Geometrie
        self.regions: list[dict] = []
        self.levels: dict[str, str] = {}
        for code, units in sorted(units_by_country.items()):
            self._build_country(code, units)

        self._by_country = collections.defaultdict(list)
        for region in self.regions:
            self._by_country[region["cc"]].append(region)
        self._trees = {
            cc: STRtree([r["geometry"] for r in regions]) for cc, regions in self._by_country.items()
        }

    def _build_country(self, code: str, units: list) -> None:
        if code in SKIP_COUNTRIES or len(units) < 2:
            return
        shapes = [shape(u["geometry"]).buffer(0) for u in units]
        if _area_sqkm(shapes) < MIN_COUNTRY_AREA_SQKM:
            return

        # Mögliche Ebenen: die Einheiten selbst oder ihre Bündelung durch Natural Earth.
        candidates = {"units": lambda p: p["adm1_code"]}
        for field in ("region", "region_sub"):
            candidates[field] = lambda p, f=field: p[f] or p["adm1_code"]
        counts = {level: len({key(u["properties"]) for u in units}) for level, key in candidates.items()}
        level = min(counts, key=lambda lv: (_fit(counts[lv]), lv != "units"))
        key = candidates[level]
        if code in LEVEL_OVERRIDES:
            level, key = LEVEL_OVERRIDES[code]
            counts[level] = len({key(u["properties"]) for u in units})
        if counts[level] < 2:
            return
        self.levels[code] = f"{level} ({len(units)} Einheiten)"

        grouped = collections.defaultdict(list)
        for unit in units:
            grouped[key(unit["properties"])].append(unit)

        names, geometries = [], []
        for group_key, members in grouped.items():
            props = members[0]["properties"]
            if level == "nations":
                name = group_key
            elif level != "units" and props[level]:
                name = props[level]
            else:
                name = props.get("name_de") or props.get("name") or group_key
            geometry = shapely.union_all([shapes[units.index(m)] for m in members])
            names.append((group_key, name))
            geometries.append(geometry)

        # Auf den Länderumriss zuschneiden, dann gemeinsam vereinfachen: Nachbarn behalten ihre
        # gemeinsame Grenze, die Außenkante bleibt die des Landes.
        min_x, _, max_x, _ = shapely.total_bounds(geometries)
        tolerance = min(max((max_x - min_x) * SIMPLIFY_PER_DEGREE_WIDTH, SIMPLIFY_MIN), SIMPLIFY_MAX)
        if code in self.outlines:
            geometries = fit_to_outline(geometries, self.outlines[code])
        for (group_key, name), geometry in zip(names, simplify_coverage(geometries, tolerance)):
            if geometry.is_empty:
                continue
            self.regions.append({
                "id": f"{code}:{group_key}",
                "cc": code,
                "name": name,
                "geometry": geometry,
            })

    def region_id(self, cc: str, lat: float, lon: float) -> str | None:
        """Region, in der der Punkt liegt, sonst die nächste des Landes innerhalb von ~10 km."""
        tree = self._trees.get(cc)
        if tree is None:
            return None
        point = Point(lon, lat)
        regions = self._by_country[cc]
        for index in tree.query(point, predicate="intersects"):
            return regions[index]["id"]
        index = tree.query_nearest(point, max_distance=NEAREST_MAX_DEG)
        return regions[index[0]]["id"] if len(index) else None

    def write(self, path: pathlib.Path) -> None:
        out = []
        for region in self.regions:
            polygons = [g for g in shapely.get_parts(region["geometry"]) if g.geom_type == "Polygon"]
            rings = [
                [[round(v, 4) for xy in ring.coords for v in xy]
                 for ring in [polygon.exterior, *polygon.interiors]]
                for polygon in polygons if not polygon.is_empty
            ]
            if rings:
                out.append({"id": region["id"], "cc": region["cc"], "name": region["name"], "polygons": rings})
        path.write_bytes(deflate(json.dumps({"regions": out}, separators=(",", ":"), ensure_ascii=False)))
