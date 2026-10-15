#!/usr/bin/env python3
"""Lädt die Rohdaten für die Offline-Zuordnung nach tools/raw/.

Natural Earth (gemeinfrei) und GeoNames (CC BY 4.0). Läuft nur beim Aufbereiten,
nie in der App.
"""
import pathlib
import subprocess
import zipfile

RAW = pathlib.Path(__file__).resolve().parent / "raw"

SOURCES = {
    "ne_50m_admin_0_countries.geojson":
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson",
    # Nur für Kleinstaaten, deren 1:50m-Umriss zu grob ist (der Vatikan liegt dort ~1 km daneben).
    "ne_10m_admin_0_countries.geojson":
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson",
    # Regionen (Bundesländer, Staaten, Provinzen) für die Länderansicht.
    "ne_10m_admin_1_states_provinces.geojson":
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson",
    # Flüsse und Seen
    **{f"{name}.geojson": f"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/{name}.geojson"
       for name in ["ne_10m_rivers_lake_centerlines", "ne_10m_rivers_europe", "ne_10m_lakes", "ne_10m_lakes_europe"]},
    "cities15000.zip": "https://download.geonames.org/export/dump/cities15000.zip",
    "alternateNamesV2.zip": "https://download.geonames.org/export/dump/alternateNamesV2.zip",
}


def main() -> None:
    RAW.mkdir(exist_ok=True)
    for name, url in SOURCES.items():
        target = RAW / name
        if target.exists():
            print(f"vorhanden: {name}")
            continue
        print(f"lade {url}")
        # curl statt urllib: nutzt die System-Zertifikate, die dem python.org-Python oft fehlen.
        subprocess.run(["curl", "-fL", "--progress-bar", "-o", str(target), url], check=True)

    with zipfile.ZipFile(RAW / "cities15000.zip") as z:
        z.extract("cities15000.txt", RAW)
    with zipfile.ZipFile(RAW / "alternateNamesV2.zip") as z:
        if not (RAW / "alternateNamesV2.txt").exists():
            z.extract("alternateNamesV2.txt", RAW)
    print("fertig")


if __name__ == "__main__":
    main()
