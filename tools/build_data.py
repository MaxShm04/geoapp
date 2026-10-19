#!/usr/bin/env python3
"""Bereitet die Rohdaten aus tools/raw/ für das App-Paket auf.

Ausgabe nach GeoCore/Sources/GeoCore/Resources/:
  countries.json  Ländergrenzen (Natural Earth 1:50m, Kleinstaaten 1:10m)
  cities.tsv      Städte ab 15.000 Einwohnern (GeoNames), englische Namen, Einwohner, Region
  city_names.tsv  Städtenamen in den Sprachen CITY_NAME_LANGS, nur wo sie vom englischen abweichen
  regions.json.z  Regionen für die Länderansicht (Natural Earth Admin-1, siehe build_regions.py)
  CityDetail/     Wasser, Parks, Straßen für Großstädte (OpenStreetMap, eigenes Skript build_citydetail.py)
  Districts/      Kreise pro Land für die Detailansicht (siehe build_districts.py)

Vorher: python3 tools/fetch_data.py
Aufruf mit der lokalen Umgebung (braucht shapely): tools/.venv/bin/python tools/build_data.py
"""
import collections
import datetime
import json
import math
import pathlib

import shapely

from build_districts import Districts
from build_regions import Regions

TOOLS = pathlib.Path(__file__).resolve().parent
RAW = TOOLS / "raw"
OUT = TOOLS.parent / "GeoCore" / "Sources" / "GeoCore" / "Resources"

# Gebiete ohne ISO-Code bei Natural Earth. Sie werden dem Land zugeordnet, dessen Code auch
# GeoNames für die Städte dort verwendet, damit Land und Stadt zusammenpassen.
NO_ISO_CODE = {"SOL": "SO", "CYN": "CY", "KAS": "IN"}

# Überseegebiete, die Natural Earth zum Mutterland zählt, ISO und GeoNames aber als eigenes Gebiet
# führen. Ohne Trennung färbt ein Besuch in Paris auch Französisch-Guayana und La Réunion ein.
# Mutterland: [(Code, englischer Name, Ausschnitt min_lon, min_lat, max_lon, max_lat)]
OVERSEAS = {
    "FR": [
        ("GF", "French Guiana", (-55.0, 1.5, -51.0, 6.5)),
        ("GP", "Guadeloupe", (-62.0, 15.8, -60.9, 16.6)),
        ("MQ", "Martinique", (-61.3, 14.3, -60.7, 15.0)),
        ("RE", "Réunion", (55.0, -21.5, 56.0, -20.8)),
        ("YT", "Mayotte", (44.9, -13.1, 45.4, -12.5)),
    ],
    "NL": [
        ("BQ", "Caribbean Netherlands", (-68.5, 11.9, -62.9, 17.7)),
    ],
}

# Einträge mit demselben Gemeindecode gelten als Teil der größten Stadt dieser Gemeinde
# (Arrondissements, Stadtteile), sofern sie nicht weiter als das hier entfernt liegen.
MERGE_MAX_KM = 20.0

# Länder, deren Umriss kleiner als das (in Quadratgrad) ist, kommen aus 1:10m statt 1:50m.
MICROSTATE_MAX_AREA = 0.05

# Übrig gebliebene Stadtteile (PPLX) gehören zur nächsten größeren Stadt im selben Land
# innerhalb dieser Entfernung (z. B. Esquilino zu Rom, das einen gröberen Gemeindecode hat).
SECTION_MAX_KM = 15.0

# Großstädte schlucken kleinere Orte in ihrem Umkreis (z. B. Stepney und Croydon zu London).
# Der Radius wächst mit der Wurzel der Einwohnerzahl: London ~18 km, Berlin ~11 km, Paris ~9 km,
# eine Stadt mit 500.000 Einwohnern ~4 km. Nur innerhalb derselben Region (admin1), damit etwa
# Newark nicht zu New York wird. Hauptstädte zählen regionsübergreifend (Hongkong hat Distrikte als admin1).
METRO_MIN_POP = 500_000
METRO_KM_PER_SQRT_THOUSAND = 0.19
METRO_MAX_SIZE_RATIO = 0.5

# Wüstungen, zerstörte oder historische Orte.
SKIP_FEATURE_CODES = {"PPLH", "PPLQ", "PPLW"}

# Sprachen, in denen Städtenamen in city_names.tsv stehen (Wave 2 folgt aus denselben Daten).
CITY_NAME_LANGS = ("de", "fr", "es", "it", "nl", "pt")


def country_code(props: dict) -> str:
    code = props["ISO_A2_EH"]
    if code and code != "-99":
        return code
    return NO_ISO_CODE.get(props["ADM0_A3"], props["ADM0_A3"])


def polygons_of(feature: dict) -> list:
    geometry = feature["geometry"]
    return geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]


def flat_rings(polygon: list) -> list:
    # Ringe als flache Liste [lon, lat, lon, lat, ...]; erster Ring außen, weitere sind Löcher.
    return [[round(v, 5) for point in ring for v in point[:2]] for ring in polygon]


def bbox_area(polygons: list) -> float:
    xs = [v for p in polygons for v in p[0][0::2]]
    ys = [v for p in polygons for v in p[0][1::2]]
    return (max(xs) - min(xs)) * (max(ys) - min(ys))


def split_overseas(merged: dict[str, dict]) -> None:
    """Löst die Überseegebiete (OVERSEAS) als eigene Einträge aus ihrem Mutterland heraus."""
    for parent, territories in OVERSEAS.items():
        entry = merged[parent]
        for code, name, (min_lon, min_lat, max_lon, max_lat) in territories:
            def inside(polygon: list) -> bool:
                outer = polygon[0]
                lon = (min(outer[0::2]) + max(outer[0::2])) / 2
                lat = (min(outer[1::2]) + max(outer[1::2])) / 2
                return min_lon <= lon <= max_lon and min_lat <= lat <= max_lat
            parts = [p for p in entry["polygons"] if inside(p)]
            if not parts:
                raise SystemExit(f"Überseegebiet {code} nicht in {parent} gefunden")
            entry["polygons"] = [p for p in entry["polygons"] if not inside(p)]
            merged.setdefault(code, {"code": code, "name": name, "polygons": []})["polygons"].extend(parts)


def build_countries() -> dict[str, str]:
    """Schreibt countries.json und gibt die Zuordnung ADM0_A3 -> Ländercode zurück."""
    data = json.loads((RAW / "ne_50m_admin_0_countries.geojson").read_text())
    merged: dict[str, dict] = {}
    adm0_to_code: dict[str, str] = {}
    for feature in data["features"]:
        props = feature["properties"]
        code = country_code(props)
        adm0_to_code[props["ADM0_A3"]] = code
        if props["ISO_A3_EH"] and props["ISO_A3_EH"] != "-99":
            adm0_to_code.setdefault(props["ISO_A3_EH"], code)
        entry = merged.setdefault(code, {"code": code, "name": props["NAME_EN"], "polygons": []})
        # Mehrere Teile pro Code (z. B. Australien und seine Außengebiete): Name des Kernlandes.
        if props.get("HOMEPART") == 1 and props["ADM0_A3"] not in NO_ISO_CODE:
            entry["name"] = props["NAME_EN"]
        entry["polygons"].extend(flat_rings(p) for p in polygons_of(feature))
    split_overseas(merged)

    # Kleinstaaten (Vatikan, Monaco, San Marino, ...) sind in 1:50m zu grob, dafür 1:10m.
    fine = json.loads((RAW / "ne_10m_admin_0_countries.geojson").read_text())
    replaced = []
    for feature in fine["features"]:
        code = country_code(feature["properties"])
        entry = merged.get(code)
        if entry and bbox_area(entry["polygons"]) < MICROSTATE_MAX_AREA:
            entry["polygons"] = [flat_rings(p) for p in polygons_of(feature)]
            replaced.append(code)

    countries = sorted(merged.values(), key=lambda c: c["code"])
    (OUT / "countries.json").write_text(json.dumps({"countries": countries}, separators=(",", ":")))
    print(f"countries.json: {len(countries)} Länder, 1:10m für {', '.join(sorted(replaced))}")
    return adm0_to_code


def country_outlines() -> dict:
    """Länderumrisse genau so, wie sie in countries.json stehen und die App sie zeichnet.
    Regionen und Kreise werden daran ausgerichtet."""
    outlines = {}
    for country in json.loads((OUT / "countries.json").read_text())["countries"]:
        polygons = [shapely.Polygon(list(zip(rings[0][0::2], rings[0][1::2])),
                                    [list(zip(hole[0::2], hole[1::2])) for hole in rings[1:]])
                    for rings in country["polygons"]]
        outlines[country["code"]] = shapely.make_valid(shapely.union_all(polygons))
    return outlines


def haversine_km(lat1, lon1, lat2, lon2) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def alternate_names(ids: set[str]) -> tuple[dict[str, str], dict[tuple[str, str], str]]:
    """Bevorzugter englischer Name je geonameid und Namen je (geonameid, Sprache) aus alternateNamesV2.

    Je Sprache gewinnt der bevorzugte Name, sonst der nicht kurze, sonst der erste in der Datei.
    Umgangssprachliche und historische Namen fallen überall weg."""
    english: dict[str, str] = {}
    best: dict[tuple[str, str], tuple[tuple[bool, bool], str]] = {}
    with open(RAW / "alternateNamesV2.txt", encoding="utf-8") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            # alternateNameId, geonameid, isolanguage, name, isPreferred, isShort, isColloquial, isHistoric, from, to
            if cols[1] not in ids or cols[6] == "1" or cols[7] == "1":
                continue
            lang = cols[2]
            if lang == "en":
                if cols[4] == "1":
                    english.setdefault(cols[1], cols[3])
            elif lang in CITY_NAME_LANGS and cols[3]:
                rank = (cols[4] != "1", cols[5] == "1")
                key = (cols[1], lang)
                if key not in best or rank < best[key][0]:
                    best[key] = (rank, cols[3])
    return english, {key: name for key, (_, name) in best.items()}


def metro_radius_km(pop: int) -> float:
    return METRO_KM_PER_SQRT_THOUSAND * math.sqrt(pop / 1000)


def absorb_into_metros(rows: list, parent: dict) -> None:
    """Ordnet eigenständige Orte im Umkreis einer Großstadt dieser Großstadt zu."""
    independent = [r for r in rows if r["id"] not in parent]
    metros = sorted((r for r in independent if r["pop"] >= METRO_MIN_POP), key=lambda r: -r["pop"])
    for metro in metros:
        if metro["id"] in parent:
            continue  # bereits von einer noch größeren Stadt geschluckt
        radius = metro_radius_km(metro["pop"])
        max_dlat = radius / 110.0
        for r in independent:
            if r is metro or r["id"] in parent or r["cc"] != metro["cc"]:
                continue
            if r["pop"] > metro["pop"] * METRO_MAX_SIZE_RATIO or abs(r["lat"] - metro["lat"]) > max_dlat:
                continue
            same_region = r["admin"][1] == metro["admin"][1] or metro["feature"] == "PPLC"
            if same_region and haversine_km(r["lat"], r["lon"], metro["lat"], metro["lon"]) <= radius:
                parent[r["id"]] = metro["id"]


def build_cities(regions: Regions, districts: Districts) -> None:
    rows = []
    with open(RAW / "cities15000.txt", encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            if c[7] in SKIP_FEATURE_CODES:
                continue
            rows.append({
                "id": c[0], "name": c[1], "lat": float(c[4]), "lon": float(c[5]),
                "feature": c[7], "cc": c[8], "admin": (c[8], c[10], c[11], c[12], c[13]),
                "pop": int(c[14] or 0),
            })

    # Gruppen nach Gemeinde: admin4, sonst admin3. Ohne beide wird nicht zusammengefasst.
    groups = collections.defaultdict(list)
    for r in rows:
        cc, a1, a2, a3, a4 = r["admin"]
        if a4:
            groups[(cc, a1, a2, a3, a4)].append(r)
        elif a3:
            groups[(cc, a1, a2, a3)].append(r)

    parent: dict[str, str] = {}
    for members in groups.values():
        if len(members) < 2:
            continue
        keeper = max(members, key=lambda r: (r["feature"] != "PPLX", r["pop"]))
        for r in members:
            if r is not keeper and haversine_km(r["lat"], r["lon"], keeper["lat"], keeper["lon"]) <= MERGE_MAX_KM:
                parent[r["id"]] = keeper["id"]

    by_country = collections.defaultdict(list)
    for r in rows:
        if r["id"] not in parent and r["feature"] != "PPLX":
            by_country[r["cc"]].append(r)
    for r in rows:
        if r["id"] in parent or r["feature"] != "PPLX":
            continue
        candidates = [
            (haversine_km(r["lat"], r["lon"], c["lat"], c["lon"]), c)
            for c in by_country[r["cc"]]
            if c["pop"] > r["pop"] and abs(c["lat"] - r["lat"]) < 0.2
        ]
        candidates = [(km, c) for km, c in candidates if km <= SECTION_MAX_KM]
        if candidates:
            parent[r["id"]] = min(candidates, key=lambda kc: kc[0])[1]["id"]

    absorb_into_metros(rows, parent)

    # Ketten auflösen (Stadtteil -> Stadtteil -> Stadt), damit jeder Punkt direkt auf eine Stadt zeigt.
    for child in list(parent):
        root = parent[child]
        while root in parent:
            root = parent[root]
        parent[child] = root

    keepers = [r for r in rows if r["id"] not in parent]
    names, local_names = alternate_names({r["id"] for r in keepers})

    # Einwohner einer Stadt inklusive ihrer Stadtteile und geschluckten Orte.
    population = {r["id"]: r["pop"] for r in keepers}
    for r in rows:
        if r["id"] in parent:
            population[parent[r["id"]]] = max(population[parent[r["id"]]], r["pop"])

    # Zeilen: id, parent, cc, lat, lon, name, einwohner, region, kreis. Zusätzliche Bezugspunkte
    # (Stadtteile) haben eine parent-ID und sonst nur Koordinaten, eigenständige Städte ein leeres parent-Feld.
    lines = []
    local_lines = []
    without_region = 0
    for r in sorted(keepers, key=lambda r: int(r["id"])):
        name = names.get(r["id"], r["name"]).replace("\t", " ")
        region = regions.region_id(r["cc"], r["lat"], r["lon"]) or ""
        district = districts.district_id(r["cc"], r["lat"], r["lon"]) or ""
        without_region += not region
        lines.append(f'{r["id"]}\t\t{r["cc"]}\t{r["lat"]:.4f}\t{r["lon"]:.4f}\t{name}\t{population[r["id"]]}\t{region}\t{district}')
        # Nur Namen, die vom englischen abweichen; Munich bleibt in Französisch ohne Zeile.
        for lang in sorted(CITY_NAME_LANGS):
            local = local_names.get((r["id"], lang), "").replace("\t", " ")
            if local and local != name:
                local_lines.append(f'{r["id"]}\t{lang}\t{local}')
    for r in sorted((r for r in rows if r["id"] in parent), key=lambda r: int(r["id"])):
        lines.append(f'{r["id"]}\t{parent[r["id"]]}\t{r["cc"]}\t{r["lat"]:.4f}\t{r["lon"]:.4f}\t\t\t\t')
    (OUT / "cities.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (OUT / "city_names.tsv").write_text("\n".join(local_lines) + "\n", encoding="utf-8")
    print(f"cities.tsv: {len(keepers)} Städte, {len(parent)} zusätzliche Bezugspunkte, "
          f"{sum(1 for r in keepers if r['id'] in names)} englische Namen, {without_region} ohne Region")
    print(f"city_names.tsv: {len(local_lines)} Namen in {len(CITY_NAME_LANGS)} Sprachen")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    adm0_to_code = build_countries()
    regions = Regions(RAW, adm0_to_code, country_outlines())
    (OUT / "regions.json").unlink(missing_ok=True)
    regions.write(OUT / "regions.json.z")
    print(f"regions.json: {len(regions.regions)} Regionen in {len(regions.levels)} Ländern")
    for cc in ["DE", "FR", "GB", "IT", "ES", "US", "CH", "JP", "SI", "CN"]:
        print(f"  {cc}: {sum(r['cc'] == cc for r in regions.regions)} Regionen, {regions.levels.get(cc)}")
    districts = Districts(RAW, regions, adm0_to_code)
    size = districts.write(OUT / "Districts")
    print(f"Districts/: {sum(map(len, districts.by_country.values()))} Kreise in {len(districts.by_country)} Ländern, "
          f"{size / 1e6:.1f} MB")
    for cc in ["DE", "FR", "GB", "IT", "ES", "US", "CH", "AT", "JP", "NL", "PL"]:
        print(f"  {cc}: {districts.levels.get(cc)}")
    build_cities(regions, districts)
    (OUT / "water.json.z").unlink(missing_ok=True)  # Seen und Flüsse zeigt die Karte nicht mehr
    # Neuer Stand: Die App gleicht gespeicherte Städte beim nächsten Start einmal an (CityRemapping).
    version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (OUT / "data_version.txt").write_text(version + "\n")
    print(f"data_version.txt: {version}")


if __name__ == "__main__":
    main()
