#!/usr/bin/env python3
"""Stadtdetails aus OpenStreetMap für Großstädte: Wasserflächen, Parks und Hauptstraßen.

Für jede Stadt ab MIN_POPULATION Einwohnern (aus cities.tsv) wird einmalig per Overpass-API
abgefragt, was im Umkreis der Stadt liegt. Die Antworten landen in tools/raw/osm/ und werden bei
einem erneuten Lauf wiederverwendet; das Skript lässt sich also jederzeit abbrechen und fortsetzen.

Ausgabe nach GeoCore/Sources/GeoCore/Resources/CityDetail/:
  <geonameid>.json.z  komprimiertes JSON mit water, parks, roads (vereinfacht, ~20 m)
  _index.json         Liste der Städte mit Ausschnitt, damit die App weiß, wo es Details gibt

Daten © OpenStreetMap-Mitwirkende, Lizenz ODbL. Aufruf:
  tools/.venv/bin/python tools/build_citydetail.py [--limit N] [--only NAME]
"""
import argparse
import json
import math
import pathlib
import subprocess
import sys
import time

import zlib

import shapely
import shapely.affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import linemerge, polygonize, unary_union

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from build_districts import deflate  # noqa: E402

TOOLS = pathlib.Path(__file__).resolve().parent
RAW = TOOLS / "raw" / "osm"
RESOURCES = TOOLS.parent / "GeoCore" / "Sources" / "GeoCore" / "Resources"
OUT = RESOURCES / "CityDetail"

MIN_POPULATION = 1_000_000
INCLUDE_AREAS = False
# Umkreis wie bei der Zuordnung von Vororten (London ~18 km), mindestens 10, höchstens 30 km.
RADIUS_KM_PER_SQRT_THOUSAND = 0.19
RADIUS_MIN_KM, RADIUS_MAX_KM = 10.0, 30.0
# Kleinere Flächen fallen weg (Teiche, Pocket Parks), in Quadratkilometern.
MIN_WATER_SQKM = 0.01
MIN_PARK_SQKM = 0.08
# Vereinfachung in Grad (~20 m) und Rundung auf ~10 m.
SIMPLIFY = 0.0002
DECIMALS = 4

ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
USER_AGENT = "GeoApp-prototype-databuild/0.1 (private, one-off city extracts)"

QUERY = """[out:json][timeout:300][bbox:{s},{w},{n},{e}];
(
  way["natural"="water"]; relation["natural"="water"];
  way["waterway"="riverbank"]; relation["waterway"="riverbank"];
  way["leisure"~"^(park|nature_reserve|common)$"]; relation["leisure"~"^(park|nature_reserve)$"];
  way["highway"~"^(motorway|trunk|primary)$"];
);
out geom;"""

ROAD_CLASS = {"motorway": 0, "trunk": 1, "primary": 2}


def cities() -> list[dict]:
    rows = []
    for line in (RESOURCES / "cities.tsv").read_text(encoding="utf-8").splitlines():
        cols = line.split("\t")
        if len(cols) < 7 or cols[1] or not cols[6] or int(cols[6]) < MIN_POPULATION:
            continue
        rows.append({"id": cols[0], "cc": cols[2], "name": cols[5], "lat": float(cols[3]), "lon": float(cols[4]),
                     "pop": int(cols[6])})
    return sorted(rows, key=lambda r: -r["pop"])


def _circle(city: dict):
    """Umkreis der Stadt als Fläche in Grad (Ellipse wegen der Längengrade)."""
    radius = min(max(RADIUS_KM_PER_SQRT_THOUSAND * math.sqrt(city["pop"] / 1000), RADIUS_MIN_KM), RADIUS_MAX_KM)
    circle = Point(0, 0).buffer(radius / 110.574, 48)
    return shapely.affinity.translate(
        shapely.affinity.scale(circle, xfact=1 / math.cos(math.radians(city["lat"])), yfact=1.0, origin=(0, 0)),
        city["lon"], city["lat"])


def clip_area(city: dict):
    """Fläche, für die es Details gibt: alle Kreise, die den Umkreis der Stadt berühren.

    So enden Straßen und Wasser an einer Grenze, die auf der Karte ohnehin zu sehen ist, statt
    an einer Kante mitten in der Stadt. Sind die Kreise riesig (etwa US-Counties), bleibt es beim
    Umkreis selbst.
    """
    circle = _circle(city)
    path = RESOURCES / "Districts" / f"{city['cc']}.json.z"
    if path.exists():
        data = json.loads(zlib.decompress(path.read_bytes(), -15))
        touching = []
        for district in data["districts"]:
            polygons = [Polygon(rings[0][i:i + 2] for i in range(0, len(rings[0]) - 1, 2)) for rings in district["polygons"]]
            area = unary_union([p.buffer(0) for p in polygons])
            if area.intersects(circle) and area.intersection(circle).area > 0.15 * min(area.area, circle.area):
                touching.append(area)
        if touching:
            union = unary_union(touching)
            minx, miny, maxx, maxy = union.bounds
            cminx, cminy, cmaxx, cmaxy = circle.bounds
            if (maxx - minx) <= 2.2 * (cmaxx - cminx) and (maxy - miny) <= 2.2 * (cmaxy - cminy):
                return union.buffer(0)
    return circle


def bbox_for(city: dict) -> tuple[float, float, float, float]:
    minx, miny, maxx, maxy = clip_area(city).bounds
    return miny, minx, maxy, maxx


def fetch(city: dict, attempts: int = 8) -> dict | None:
    cache = RAW / f"{city['id']}-v2.json"
    if cache.exists():
        return json.loads(cache.read_text())
    s, w, n, e = bbox_for(city)
    query = QUERY.format(s=s, w=w, n=n, e=e)
    for attempt in range(attempts):
        endpoint = ENDPOINTS[attempt % len(ENDPOINTS)]
        result = subprocess.run(
            ["curl", "-s", "-m", "360", "-A", USER_AGENT, "--data-urlencode", f"data={query}", endpoint],
            capture_output=True)
        body = result.stdout
        if body.startswith(b"{"):
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = None
            if data is not None and "remark" not in data:
                cache.write_bytes(body)
                return data
        wait = min(30 * (attempt + 1), 180)
        print(f"  {city['name']}: kein Ergebnis von {endpoint.split('/')[2]}, neuer Versuch in {wait} s", flush=True)
        time.sleep(wait)
    return None


def _polygons_from_relation(element: dict) -> list[Polygon]:
    outer, inner = [], []
    for member in element.get("members", []):
        geometry = member.get("geometry")
        if member.get("type") != "way" or not geometry or len(geometry) < 2:
            continue
        line = LineString([(p["lon"], p["lat"]) for p in geometry])
        (inner if member.get("role") == "inner" else outer).append(line)
    if not outer:
        return []
    # OSM-Relationen sind nicht immer sauber geschlossen oder überschneiden sich: erst reparieren.
    shells = [shapely.make_valid(p) for p in polygonize(linemerge(outer))]
    holes = [shapely.make_valid(p) for p in polygonize(linemerge(inner))] if inner else []
    area = unary_union(shells)
    if holes:
        area = area.difference(unary_union(holes))
    return [g for g in shapely.get_parts(area) if g.geom_type == "Polygon"]


def _area_sqkm(geometry, lat: float) -> float:
    return geometry.area * 110.574 * 111.320 * math.cos(math.radians(lat))


def build(city: dict, data: dict) -> dict:
    clip = clip_area(city)
    w, s, e, n = clip.bounds
    water, parks, roads = [], [], []
    for element in data.get("elements", []):
        tags = element.get("tags", {})
        if "highway" in tags:
            geometry = element.get("geometry")
            if element["type"] == "way" and geometry and len(geometry) >= 2:
                roads.append((ROAD_CLASS.get(tags["highway"], 2), LineString([(p["lon"], p["lat"]) for p in geometry])))
            continue
        try:
            if element["type"] == "way":
                geometry = element.get("geometry") or []
                if len(geometry) < 4 or geometry[0] != geometry[-1]:
                    continue
                polygons = [Polygon([(p["lon"], p["lat"]) for p in geometry])]
            else:
                polygons = _polygons_from_relation(element)
        except (shapely.errors.GEOSException, ValueError):
            continue  # kaputte Geometrie in OSM: diese eine Fläche auslassen
        is_water = tags.get("natural") == "water" or tags.get("waterway") == "riverbank"
        (water if is_water else parks).extend(shapely.make_valid(p) for p in polygons)

    def areas(polygons, minimum):
        parts = [g for p in polygons for g in shapely.get_parts(p) if g.geom_type == "Polygon" and not g.is_empty]
        merged = unary_union(parts).intersection(clip)
        merged = merged.simplify(SIMPLIFY, preserve_topology=True)
        return [p for p in shapely.get_parts(merged)
                if p.geom_type == "Polygon" and _area_sqkm(p, city["lat"]) >= minimum]

    def rings(polygon):
        return [[round(v, DECIMALS) for xy in ring.coords for v in xy] for ring in [polygon.exterior, *polygon.interiors]]

    road_out = []
    for road_class in (0, 1, 2):
        merged = linemerge(unary_union([line for c, line in roads if c == road_class]).intersection(clip))
        for part in shapely.get_parts(merged):
            if part.geom_type == "LineString" and part.length > 0:
                part = part.simplify(SIMPLIFY)
                road_out.append({"c": road_class, "l": [round(v, DECIMALS) for xy in part.coords for v in xy]})

    return {
        "bbox": [round(w, 4), round(s, 4), round(e, 4), round(n, 4)],
        # Wasser und Parks sind derzeit ausgeblendet. Die Rohdaten bleiben im Zwischenspeicher,
        # mit INCLUDE_AREAS = True kommen sie ohne neues Laden zurück.
        "water": [rings(p) for p in areas(water, MIN_WATER_SQKM)] if INCLUDE_AREAS else [],
        "parks": [rings(p) for p in areas(parks, MIN_PARK_SQKM)] if INCLUDE_AREAS else [],
        "roads": road_out,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="nur die N größten Städte")
    parser.add_argument("--only", default="", help="nur Städte mit diesem Namen")
    args = parser.parse_args()

    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    selection = cities()
    if args.only:
        selection = [c for c in selection if c["name"] == args.only]
    if args.limit:
        selection = selection[:args.limit]

    index_path = OUT / "_index.json"
    index = {entry["id"]: entry for entry in json.loads(index_path.read_text())} if index_path.exists() else {}
    for number, city in enumerate(selection, 1):
        print(f"[{number}/{len(selection)}] {city['name']}", flush=True)
        data = fetch(city)
        if data is None:
            print(f"  übersprungen: {city['name']}", flush=True)
            continue
        try:
            detail = build(city, data)
        except Exception as error:  # eine Stadt darf den Lauf nicht abbrechen
            print(f"  übersprungen: {city['name']} ({error})", flush=True)
            continue
        (OUT / f"{city['id']}.json.z").write_bytes(deflate(json.dumps(detail, separators=(",", ":"))))
        index[city["id"]] = {"id": city["id"], "bbox": detail["bbox"]}
        index_path.write_text(json.dumps(sorted(index.values(), key=lambda x: int(x["id"])), separators=(",", ":")))
        print(f"  {len(detail['water'])} Wasser, {len(detail['parks'])} Parks, {len(detail['roads'])} Straßen", flush=True)
        time.sleep(2)  # Overpass schonen
    total = sum(p.stat().st_size for p in OUT.glob("*.json.z"))
    print(f"CityDetail/: {len(index)} Städte, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
