# GeoApp

An iOS app that records in the background which countries and cities you have visited and shows them on a calm world map. Everything stays on the device.

## Privacy

- No raw coordinates are stored. A position is mapped to a city and country, then latitude and longitude are discarded.
- No network: no accounts, servers, analytics, ad SDKs or online geocoders. Geocoding runs offline against bundled data.

## Repository layout

| Path | Contents |
| --- | --- |
| `GeoApp/` | The iOS app (Xcode project, widgets, tests, GPX files for simulated locations) |
| `GeoCore/` | Swift package with the core logic: offline geocoding, visit rules, data model |
| `tools/` | Python scripts that build the offline geo data from Natural Earth and GeoNames |
| `docs/phases/` | Plans and test specs of finished phases |
| `ROADMAP.md` | Current state and next steps |

## Build and test

Requires Xcode with the iOS 17+ SDK.

```bash
open GeoApp/GeoApp.xcodeproj
```

Core package tests:

```bash
cd GeoCore && swift test
```

App tests in the simulator:

```bash
xcodebuild -project GeoApp/GeoApp.xcodeproj -scheme GeoApp -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The generated geo data is checked in under `GeoCore/Sources/GeoCore/Resources/`. To rebuild it, set up the Python tools and fetch the raw data (over 1 GB) with `tools/fetch_data.py`:

```bash
python3 -m venv tools/.venv && tools/.venv/bin/pip install -r tools/requirements.txt
```

## Data sources

- [Natural Earth](https://www.naturalearthdata.com/) (public domain): country and region boundaries
- [GeoNames](https://www.geonames.org/) (CC BY 4.0): cities
