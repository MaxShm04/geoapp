# Phase 2: Time & stories

Status: **done** (Oct 19, 2026) · committed as 12f1541 on `phase-2-time-stories` (not pushed) · Plan written Oct 19, 2026 · Branch `phase-2-time-stories` (from 33e5426) · See `ROADMAP.md`, Phase 2

## Goal

Give people reasons to open the app without push notifications, and ship the main Pro content: a year filter on the map, home region and trip detection with a timeline, a statistics screen (with day-gap closing), widgets (store moved into an App Group), a Shortcut ("How many countries this year?") and the Pro gates from the Free/Pro table in `ROADMAP.md`. All new strings in English with German. Wave-2 languages are optional at the end.

## Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | **Pure time logic lives in GeoCore** (`GeoCore/Sources/GeoCore/Time/`): `DayKey`, `YearFilter`, `PlaceDay`, `GapFilling`, `HomeRegion`, `TripDetector`/`Trip`, `Statistics`/`YearStatistics`. They work on the value type `PlaceDay` (day, country, city ID, region ID, last seen, inferred). The app maps `DayVisit → PlaceDay` (`Timeline/Journal.swift`). | Testable with `swift test` in seconds, no SwiftData or simulator needed. |
| D2 | **No schema change in Phase 2.** Gap-filled days, home region, trips and statistics are derived at display time and never stored. Schema stays V2. The CloudKit schema V3 (no unique constraints, defaults everywhere, dedup after sync) remains Phase 3; it keeps the App Group store URL chosen here (D7), so the store moves only once. | Keeps the store move separate from any schema change (`ROADMAP.md`, technical notes). |
| D3 | **Gap closing:** a day without a capture gets the place last seen on the previous captured day (the entry with the latest `lastSeen` that day), marked `isInferred`. Gaps between two captured days and the trailing gap up to today are filled only when they are at most `GapFilling.maxGapDays = 30` days long; longer gaps stay empty (phone off, app not running). Used for statistics, trips and home region. The map, lists and "new places" use captured places only. | The roadmap rule ("counts where the person was last seen"), with a cap so months without data are not invented. |
| D4 | **Home region:** area key = `regionId ?? countryCode` (`PlaceDay.areaKey`). Detected as the area with the most distinct days in the 90 days ending today (gap-filled days). Ties: the area with the more recent day, then the smaller key. No days in that window → the 90 days ending at the latest day with data. Override in Settings stored as the area key in `UserDefaults.standard` (`AppSettings.homeRegionOverride`, app only; empty string = automatic). | Roadmap rule; an area key is a dataset ID, not a coordinate. |
| D5 | **Trips:** a maximal run of consecutive days that each have a place outside the home area, containing at least one day entirely away (no place in the home area, i.e. a night away). Day trips are not trips. A missing day breaks the run. `countryCodes` ordered by days in the trip (desc), ties by first appearance; `mainCountryCode` = first. `cityIds` = distinct city IDs outside the home area in order of first appearance. `isOngoing` when the trip ends today. Trips are detected relative to the current home (moving house changes history; the override is the fix). | "Consecutive days away from the home region" (`ROADMAP.md`), without turning commutes across a region border into trips. |
| D6 | **Statistics** per year (or all time, `year == nil`), on gap-filled days: countries and cities visited; days per country (distinct days, desc, ties by code); new countries/cities = first *captured* day falls in that year; travel days per month = trip days per calendar month (a trip across New Year counts in both years); longest trip = most days among trips *starting* in that year, ties → earlier. | Roadmap list: days per country and year, new places this year, travel days per month, longest trip. |
| D7 | **Store move into the App Group** `group.de.max.geoapp`: store at `<group>/Library/Application Support/GeoApp.store`. On first launch `Store.shared` calls `StoreLocation.resolve` *before* opening: it copies `default.store` + `-wal` + `-shm` from the app's Application Support (no connection is open yet) to a staging name and renames into place, main file last. The legacy files are deleted only after the copy opened successfully. A copy that fails to open is removed and the legacy store opened instead. Without the App Group (missing entitlement) the app keeps using the legacy location. Only the app opens SwiftData. | A one-off, crash-safe move: at every point either the legacy store or a complete copy exists. |
| D8 | **Widgets read a snapshot, not the store:** the app writes `widget-snapshot.json` (counts, new places this year, a few localized names) and two map images (`widget-map-light.png`, `widget-map-dark.png`, rendered from Natural Earth country outlines) into the App Group and reloads the timelines. Written after a new place is recorded, when the app goes to the background, after deletions and test data changes. The widget extension does not link GeoCore. | Widget memory limit (~30 MB), no SwiftData migration inside an extension, an extension must never create an empty store before the app moved the old one (D7), and GeoCore's geodata would double the bundle. |
| D9 | **Widget Pro check:** the extension asks StoreKit itself (`Transaction.currentEntitlements`, same rule `ProRules.isPro(facts:now:)` in `Shared/`). Nothing about Pro is stored (Phase 1 D6). Free widget: **Counter**. **New places** and **Map** show a calm locked state that opens the paywall (`geoapp://pro`). | "1 widget free, all widgets Pro" without persisting entitlement state. |
| D10 | **Gates** (`ProFeature`: `yearFilter`, `timeline` (new), `statistics`, `widgets`; all `isGated == true`): Free = map "All years" and the current year, timeline of the current year, statistics overview of the current year, Counter widget. Pro = every year on the map and in the timeline, all-time and per-year statistics with full detail (days per country, travel days per month, longest trip), all widgets. Shortcuts free. Logic in `Pro/ProGate.swift`. Phase 1 case 22 is replaced by case 52. | Free/Pro table in `ROADMAP.md`; the full map stays free (principle 2). |
| D11 | **App Intents** in the app target (`Intents/`): `CountriesThisYearIntent` ("How many countries this year?") runs in the app process without opening the UI, answer text in the catalog with plurals. Phrases in `GeoApp/GeoApp/AppShortcuts.xcstrings`. | No extension needed; uses `Store.shared`. |
| D12 | **Navigation:** tabs Map · Trips · Statistics · List · Settings. Home region row in Settings (new section "Home"). Year menu next to the map counter. | Five tabs still fit without "More". |
| D13 | **Catalogs:** workers never edit `.xcstrings`; they report new strings with German in their report. The main model syncs keys (`xcstringstool sync`, arm64 `.stringsdata` only) and merges German (Phase 1 D11). Widget strings live in `GeoApp/GeoWidgets/Localizable.xcstrings`. | Parallel catalog edits conflict. |

## Test spec

Swift Testing. Core tests in `GeoCore/Tests/GeoCoreTests/`, app tests in `GeoApp/GeoAppTests/`. Every case lists target file · setup · input → expected result. The main model writes all production signatures as stubs first (T0); test workers only write tests.

**Shared helpers.** Core tests build `PlaceDay(day:countryCode:cityId:regionId:lastSeen:isInferred:)` (`cityId`, `regionId` default `nil`, `lastSeen` default `.distantPast`, `isInferred` default `false`). Use a fixed time: `lastSeen` = `Date(timeIntervalSince1970: 0).addingTimeInterval(hours * 3600)` is enough where order matters. City IDs used: Berlin 2950159, Munich 2867714, Salzburg 2766824, Verona 3164527, Venice 3164603, Florence 3176959, Rome 3169070, Hamburg 2911298, Paris 2988507, Vienna 2761369, Zurich 2657896. Regions are plain strings (`"DE-BY"`, `"DE-HH"`, `"IT-VEN"`, `"IT-TOS"`, `"IT-LAZ"`, `"AT-SBG"`, `"FR-IDF"`, `"CH-ZH"`).

### Day keys and year filter (core)

1. `DayKeyTests.yearAndMonth` · `DayKeyTests.swift` · `DayKey.year(20260519) == 2026`, `DayKey.month(20260519) == 5`, `DayKey.month(20261201) == 12`.
2. `DayKeyTests.addingAcrossMonthAndYear` · `DayKey.adding(1, to: 20260131) == 20260201`; `adding(1, to: 20261231) == 20270101`; `adding(-1, to: 20260301) == 20260228`; `adding(1, to: 20280228) == 20280229`; `adding(0, to: 20260519) == 20260519`; `adding(30, to: 20260101) == 20260131`.
3. `DayKeyTests.daysBetween` · `DayKey.daysBetween(20260101, 20260101) == 0`; `(20260101, 20260201) == 31`; `(20261231, 20270101) == 1`; `(20260201, 20260101) == -31`; across the DST change `(20260328, 20260330) == 2`.
4. `DayKeyTests.dateRoundTrip` · calendar = Gregorian, time zone `Europe/Berlin` · `DayKey.date(20260519, calendar:)` is the start of that day in that calendar and `VisitRules.dayKey(for: thatDate, calendar:) == 20260519`; `DayKey.today(now: thatDate + 13 h, calendar:) == 20260519`.
5. `YearFilterTests.contains` · `YearFilterTests.swift` · `YearFilter.all.contains(day: 20190101) == true`; `.year(2026).contains(day: 20260519) == true`; `.year(2026).contains(day: 20251231) == false`.
6. `YearFilterTests.availableYears` · `YearFilter.availableYears(days: [20240105, 20260519, 20240210, 20250101], currentYear: 2026) == [2026, 2025, 2024]`; `(days: [], currentYear: 2026) == [2026]`; `(days: [20240105], currentYear: 2026) == [2026, 2024]`.
7. `YearFilterTests.storageRoundTrip` · `.all.storageValue == "all"`, `.year(2025).storageValue == "2025"`; `YearFilter(storageValue: "all") == .all`, `("2025") == .year(2025)`, `("garbage") == nil`, `("") == nil`.

### Gap closing (core)

8. `GapFillingTests.emptyStaysEmpty` · `GapFillingTests.swift` · `GapFilling.fill([], through: 20260110) == []`.
9. `GapFillingTests.fillsGapWithLastPlace` · Berlin (DE, 2950159, "DE-BE") on 20260101, Rome (IT, 3169070, "IT-LAZ") on 20260104; `through: 20260104` → 4 entries; 20260102 and 20260103 each exactly one entry with Berlin's country/city/region and `isInferred == true`; the two captured entries are unchanged with `isInferred == false`; output sorted by day.
10. `GapFillingTests.lastSeenPlaceOfTheDayWins` · 20260101: Munich (DE, "DE-BY") `lastSeen` 08:00 and Salzburg (AT, "AT-SBG") `lastSeen` 18:00; Munich again 20260103; `through: 20260103` → the inferred 20260102 entry is Salzburg (AT, 2766824).
11. `GapFillingTests.fillsUpToToday` · one capture 20260101 Berlin · `through: 20260104` → inferred 20260102, 20260103, 20260104 (3 inferred, 4 total); `through: 20260101` → no inferred; `through: 20251231` (today before the last capture) → no inferred.
12. `GapFillingTests.longGapIsNotFilled` · `GapFilling.maxGapDays == 30`; captures 20260101 and 20260201 (30 missing days), `through: 20260201` → 30 inferred; captures 20260101 and 20260202 (31 missing), `through: 20260202` → 0 inferred.
13. `GapFillingTests.capturedDaysAreNeverDuplicated` · captures 20260101 (Berlin), 20260102 (two entries: Berlin and Hamburg), 20260103 (Berlin); `through: 20260103` → output equals input count (4), no `isInferred`.
14. `GapFillingTests.trailingGapRespectsMax` · capture 20260101, `through: 20260301` → 0 inferred.

### Home region (core)

15. `HomeRegionTests.mostDaysInWindowWins` · `HomeRegionTests.swift` · today 20260531; "DE-BY" on each of 20260401…20260520 (50 days), "IT-LAZ" on 20260521…20260530 (10 days) → `HomeRegion.detect(days, today: 20260531) == "DE-BY"`; `HomeRegion.windowDays == 90`.
16. `HomeRegionTests.oldDaysOutsideWindowIgnored` · "DE-BY" on 200 days ending 20250101, "FR-IDF" on 10 days 20260501…20260510; today 20260531 → `"FR-IDF"`.
17. `HomeRegionTests.countsDistinctDays` · area "AT-SBG": 5 entries (different city IDs) all on 20260510; area "DE-BY": one entry each on 20260511 and 20260512; today 20260531 → `"DE-BY"`.
18. `HomeRegionTests.tieGoesToMoreRecent` · "AT-SBG" on 20260501…20260505, "CH-ZH" on 20260510…20260514; today 20260531 → `"CH-ZH"`.
19. `HomeRegionTests.noRegionFallsBackToCountry` · `PlaceDay(day:, countryCode: "MC", regionId: nil).areaKey == "MC"`; with `regionId: "DE-BY"` → `"DE-BY"`; 5 days of MC without region, today in the window → `"MC"`.
20. `HomeRegionTests.noRecentDataUsesLatestWindow` · "DE-BY" on 10 days in March 2024 only, today 20260531 → `"DE-BY"`; no days → `nil`.

### Trips (core)

All with `home = "DE-BY"` unless noted; Munich = (DE, 2867714, "DE-BY").

21. `TripTests.overnightTripIsDetected` · `TripTests.swift` · Munich 20260501…20260511; 20260512: Munich 08:00 + Verona (IT, 3164527, "IT-VEN") 18:00; 20260513 Verona; 20260514–15 Venice (3164603, "IT-VEN"); 20260516–17 Florence (3176959, "IT-TOS"); 20260518 Rome (3169070, "IT-LAZ"); 20260519: Rome 09:00 + Munich 20:00; 20260520 Munich; `TripDetector.trips(in: days, home: "DE-BY", today: 20260525)` → exactly one trip: `startDay 20260512`, `endDay 20260519`, `dayCount 8`, `mainCountryCode "IT"`, `countryCodes ["IT"]`, `cityIds [3164527, 3164603, 3176959, 3169070]`, `isOngoing false`.
22. `TripTests.dayTripIsNoTrip` · 20260509 Munich; 20260510 Munich 08:00 + Salzburg (AT, 2766824, "AT-SBG") 12:00 + Munich 20:00; 20260511 Munich → `[]`.
23. `TripTests.domesticTripOutsideHomeRegion` · Munich 20260501; Hamburg (DE, 2911298, "DE-HH") 20260502 and 20260503; Munich 20260504 → one trip 20260502–20260503, `countryCodes ["DE"]`, `mainCountryCode "DE"`, `cityIds [2911298]`.
24. `TripTests.multiCountryOrderByDays` · Munich 20260501; Salzburg 20260502–03 (2 days AT), Verona 20260504–07 (4 days IT), Zurich (CH, 2657896, "CH-ZH") 20260508 (1 day); Munich 20260509 → `countryCodes ["IT", "AT", "CH"]`, `mainCountryCode "IT"`. Second setup: Salzburg 2 days then Verona 2 days → `countryCodes ["AT", "IT"]` (tie → first appearance).
25. `TripTests.ongoingTrip` · Munich 20260520; Verona 20260521…20260525; today 20260525 → one trip, `endDay 20260525`, `isOngoing true`.
26. `TripTests.missingDayBreaksTrip` · Munich 20260510; Verona 20260512–13; no entry on 20260514; Verona 20260515–16; Munich 20260517; (20260511 also missing) → two trips: 20260512–13 and 20260515–16.
27. `TripTests.homeCitiesNotCounted` · the setup of case 21 → `cityIds` does not contain 2867714.
28. `TripTests.inferredDaysCount` · Munich 20260501; 20260512 Munich 08:00 + Verona 18:00; no captures 20260513–15; 20260516 Verona 09:00 + Munich 20:00; `GapFilling.fill(…, through: 20260516)` then trips → one trip 20260512–20260516, `dayCount 5` (the days 20260502…20260511 are filled with Munich and stay home).
29. `TripTests.sortedAndEmpty` · two trips (case 26 setup) → sorted by `startDay` ascending; `trips(in: [], …) == []`; only home days → `[]`.

### Statistics (core)

30. `StatisticsTests.daysPerCountry` · `StatisticsTests.swift` · 2026: Berlin on 20260101…20260110 (10 days), Rome 20260201…20260204 (4 days), 20260301 Munich + Salzburg; `Statistics.make(year: 2026, days:, trips: [])` → `daysPerCountry == [CountryDays(code: "DE", days: 11), CountryDays(code: "IT", days: 4), CountryDays(code: "AT", days: 1)]`. Tie order: two countries with 1 day each → ascending code.
31. `StatisticsTests.countsPerYear` · Paris (FR) 20251201, Berlin 20260105, Rome 20260210, Rome 20260211, a country-only day (MC, no city) 20260301 → `make(year: 2026)`: `countryCodes == ["DE", "IT", "MC"]` (Set), `cityIds == [2950159, 3169070]` (Set); `make(year: 2025)`: `countryCodes == ["FR"]`; `make(year: nil)`: 4 countries, 3 cities.
32. `StatisticsTests.newPlacesThisYear` · Paris captured 20251231, inferred Paris 20260101 (`isInferred: true`), Paris captured 20260105, Rome captured 20260210 → `make(year: 2026)`: `newCountryCodes == ["IT"]`, `newCityIds == [3169070]`; `make(year: 2025)`: `newCountryCodes == ["FR"]`, `newCityIds == [2988507]`. New lists are ordered by first day, ties by code/ID.
33. `StatisticsTests.travelDaysPerMonth` · trips (hand-built `Trip` values): 20260512–20260519 (8 days), 20260629–20260702 (2 June + 2 July), 20251230–20260102 (2 days in Jan 2026) → `make(year: 2026, days: [], trips:)`: `travelDaysPerMonth == [2, 0, 0, 0, 8, 2, 2, 0, 0, 0, 0, 0]`, `travelDays == 14`; `make(year: 2025)`: December = 2.
34. `StatisticsTests.longestTrip` · trips 20260512–19 (8 days), 20260801–10 (10 days), 20261001–10 (10 days), 20251220–20260105 (17 days) → `make(year: 2026).longestTrip?.startDay == 20260801`; `make(year: nil).longestTrip?.startDay == 20251220`; no trips → `nil`.
35. `StatisticsTests.emptyData` · `make(year: 2026, days: [], trips: [])` → empty sets/lists, `travelDaysPerMonth` = 12 zeros, `travelDays == 0`, `longestTrip == nil`, `trackedDays == 0`; with 3 distinct days (one inferred) → `trackedDays == 3`.

### Privacy (core)

36. `TimePrivacyTests.valueTypesHaveNoCoordinates` · `TimePrivacyTests.swift` · `Mirror` children labels of a `PlaceDay`, a `Trip`, a `YearStatistics` and a `CountryDays` contain neither `lat`/`lon` as whole camelCase words nor `latitude`, `longitude`, `coordinate`, `location`, `position` anywhere (case-insensitive). A plain substring check for `lon` would hit `longestTrip` (found by T4).

### Store move (app)

`StoreLocation` in `GeoApp/GeoApp/Data/StoreLocation.swift`. All tests use a fresh temp directory with `old/` and `group/` subfolders; legacy = `old/default.store`, destination = `group/Library/Application Support/GeoApp.store`.

37. `StoreLocationTests.freshInstall` · `StoreLocationTests.swift` · nothing exists → `StoreLocation.migrate(from: legacy, to: destination) == .freshInstall`; no file named `GeoApp.store*` exists afterwards.
38. `StoreLocationTests.movesRealStore` · create a real store at the legacy URL (`ModelContainer(for: Store.schema, migrationPlan: GeoMigrationPlan.self, configurations: ModelConfiguration(schema: Store.schema, url: legacy))`, insert 1 `Country` and 2 `DayVisit`s via `DayVisits.add`, save, release the container inside a `do {}` scope) → `migrate == .moved`; opening a container at the destination finds 1 country and 2 day visits; the legacy main file still exists.
39. `StoreLocationTests.copiesSidecars` · legacy `default.store`, `default.store-wal`, `default.store-shm` with distinct bytes (`"main"`, `"wal"`, `"shm"`) → `.moved`; destination has `GeoApp.store`, `GeoApp.store-wal`, `GeoApp.store-shm` with the same bytes; no staging file left in the destination folder (only those three files).
40. `StoreLocationTests.alreadyMovedDoesNothing` · destination main file `"new"`, legacy `"old"` → `.alreadyMoved`; destination still `"new"`; legacy still `"old"`.
41. `StoreLocationTests.interruptedMoveIsRedone` · destination folder has only a stray `GeoApp.store-wal` (`"stale"`) and a leftover staging file `GeoApp.store.moving` (`"partial"`); legacy has main `"main"` and no wal → `.moved`; destination main = `"main"`, no `GeoApp.store-wal`, no `GeoApp.store.moving`.
42. `StoreLocationTests.resolveWithoutGroup` · `StoreLocation.resolve(legacy:, group: nil)` → `url == legacy`, `outcome == .unavailable`; with a group URL and nothing on disk → `url == destination`, `.freshInstall`.
43. `StoreLocationTests.removeLegacy` · legacy main, wal, shm plus an unrelated `other.txt` in `old/` → `StoreLocation.removeLegacy(at: legacy)` removes the three store files and keeps `other.txt`; calling it again (files missing) does not throw or crash.
44. `StoreLocationTests.failedCopyKeepsLegacy` · `group/Library` is a *file*, so the destination folder cannot be created; legacy `"main"` → `migrate` returns `.failed(_)`; `resolve` returns `url == legacy` with `.failed(_)`; legacy unchanged.
45. `StoreLocationTests.openAfterMoveDeletesLegacy` · real legacy store as in 38 → `Store.makeContainer(legacy:, group:)` returns a container whose main context has the 2 day visits, `url == destination`, outcome `.moved`; afterwards the legacy main file is gone. Second call → `.alreadyMoved`, data still there.
46. `StoreLocationTests.corruptCopyFallsBack` · legacy main file contains garbage bytes (`"not a database"`) → `Store.makeContainer(legacy:, group:)` throws; afterwards no `GeoApp.store` exists at the destination and the legacy file still contains the garbage (never deleted).
47. `StoreLocationTests.appGroupEntitlements` · reads files relative to `#filePath`: `GeoApp/GeoApp.entitlements` and `GeoApp/GeoWidgets/GeoWidgets.entitlements` both contain `com.apple.security.application-groups` and `group.de.max.geoapp`; `project.pbxproj` contains `CODE_SIGN_ENTITLEMENTS = GeoApp.entitlements` and `CODE_SIGN_ENTITLEMENTS = GeoWidgets/GeoWidgets.entitlements`; `StoreLocation.appGroupID == "group.de.max.geoapp"`.

### Journal: app adapter (app)

48. `JournalTests.mapsDayVisits` · `JournalTests.swift` · in-memory store (`Store.inMemory()`), one `DayVisit` added via `DayVisits.add` (day 20260512, IT, 3169070, region "IT-LAZ", lastSeen T) → `PlaceDay(visit)` has `day 20260512`, `countryCode "IT"`, `cityId 3169070`, `regionId "IT-LAZ"`, `lastSeen T`, `isInferred false`.
49. `JournalTests.overrideWins` · visits: Munich ("DE-BY") on 20260401…20260510, Verona ("IT-VEN") 20260511–12, Munich 20260513 · `Journal.make(visits:, homeOverride: nil, today: 20260513)` → `home == "DE-BY"`, `detectedHome == "DE-BY"`, one trip; with `homeOverride: "IT-VEN"` → `home == "IT-VEN"`, `detectedHome == "DE-BY"`, trips relative to IT-VEN (two trips: 20260401–20260510 and the ongoing 20260513); `homeOverride: ""` behaves like `nil`.
50. `JournalTests.tripsNewestFirst` · two trips → `journal.trips[0].startDay > journal.trips[1].startDay`; `journal.days` contains inferred days for a 3-day capture gap.
51. `JournalTests.homeOverrideSetting` · `AppSettings.homeRegionOverride == "homeRegionOverride"`; after `AppSettings.registerDefaults()`, `UserDefaults.standard.string(forKey:)` is `nil` or `""` unless set.

### Pro gates and paywall (app)

52. `ProStoreTests.gatesOnInPhase2` · `ProStoreTests.swift`, **replaces `gatesOffInPhase1`** · `ProFeature.allCases == [.yearFilter, .timeline, .statistics, .widgets]`; `ProFeature.isGated` is `true` for each.
53. `ProGateTests.yearFilter` · `ProGateTests.swift` · `ProGate.allows(.yearFilter, year: .all, currentYear: 2026, isPro: false) == true`; `.year(2026)` → `true`; `.year(2025)` → `false`; `.year(2027)` → `false`; with `isPro: true` all `true`.
54. `ProGateTests.timelineAndStatisticsYears` · for `.timeline` and `.statistics`: `.year(2026)` free → `true`; `.year(2025)` → `false`; `.all` → `false` free, `true` with Pro.
55. `ProGateTests.statisticsDetail` · `ProGate.allowsStatisticsDetail(isPro: false) == false`; `isPro: true` → `true`.
56. `ProGateTests.widgets` · `WidgetKind.allCases == [.counter, .newPlaces, .map]`; `WidgetKind.free == .counter`; `ProGate.allowsWidget(.counter, isPro: false) == true`; `.newPlaces`, `.map` → `false`; all `true` with Pro; `WidgetKind.counter.kind == "Counter"`, `.newPlaces.kind == "NewPlaces"`, `.map.kind == "Map"`.
57. `ProGateTests.paywallCopyMatchesShippedFeatures` · `PaywallView.featureKeys == ["Every year on the map and in your trips", "Detailed statistics for every year", "All widgets for your Home Screen"]`; neither `Localizable.xcstrings` (any key) nor `Pro/PaywallView.swift` contains `upcoming` (case-insensitive).
58. `ProGateTests.proRulesShared` · `ProRules.isPro(facts:now:)` gives the same results as Phase 1 cases 14–19 for: `[]` → false; yearly +30 d → true; revoked → false; upgraded monthly only → false; `com.other.product` → false; and `ProStore.isPro(facts:now:)` delegates (same answers).

### Widgets (app)

59. `WidgetSnapshotTests.countsTotalsAndYear` · `WidgetSnapshotTests.swift` · days (captured): Berlin (DE) 20250610, Munich (DE) 20260105, Rome (IT) 20260210, country-only FR 20260301; `WidgetSnapshot.make(days:, today: 20260519, cityName: { "City \($0)" }, now: T)` → `year 2026`, `countriesTotal 3`, `citiesTotal 3`, `countriesThisYear 3`, `citiesThisYear 2`, `newCountriesThisYear 2` (IT, FR), `newCitiesThisYear 2`, `updated == T`.
60. `WidgetSnapshotTests.newPlaceNamesNewestFirst` · 4 cities first captured in 2026 on 0102 (A), 0203 (B), 0304 (C), 0405 (D), plus one city first seen 2025 and again 2026 → `newPlaceNames == ["City D", "City C", "City B"]` (max 3, newest first, city names only); inferred days are ignored for "new".
61. `WidgetSnapshotTests.roundTrip` · `WidgetSnapshot.url(in: dir) == dir/"widget-snapshot.json"`; `write(to:)` then `WidgetSnapshot.load(from:)` → equal; missing file → `nil`; garbage file → `nil`.
62. `WidgetSnapshotTests.noCoordinatesInSnapshot` · encode `WidgetSnapshot.placeholder` with `JSONEncoder`, parse as dictionary → no key contains `lat`, `lon`, `coordinate`, `location`, `position`; same for `Mirror` labels.
63. `WidgetMapTests.rendersPNG` · `WidgetMapTests.swift` · `WidgetMapRenderer.render(visited: ["DE"], size: CGSize(width: 600, height: 300), dark: false)` → non-nil `Data` starting with the PNG signature `89 50 4E 47`; decoded with `UIImage(data:)`, `cgImage.width == 600` (scale 1); the pixel at Germany (lon 10.4, lat 51.1 → `WidgetMapRenderer.point(lat:lon:in:)`) differs from the same pixel rendered with `visited: []` (sum of RGB differences > 30). `dark: true` output differs from `dark: false` at a sea pixel (lon −30, lat 30).

### Shortcuts (app)

64. `IntentTests.countriesThisYearAnswer` · `IntentTests.swift` · `CountriesThisYearIntent.answer(count: 5, year: 2026, locale: en) == "You’ve been to 5 countries in 2026."`; `1` → `"You’ve been to 1 country in 2026."`; `0` → `"No countries recorded in 2026 yet."`; `de`: 5 → `"Du warst 2026 in 5 Ländern."`, 1 → `"Du warst 2026 in 1 Land."`, 0 → `"2026 ist noch kein Land erfasst."` The year never shows a grouping separator.
65. `IntentTests.countriesThisYearCount` · in-memory store: DE 20260105, IT 20260210, IT 20260211, FR 20251231 → `CountriesThisYearIntent.count(context:, year: 2026) == 2`; `year: 2025` → 1.
66. `IntentTests.shortcutPhrasesLocalized` · parses `GeoApp/GeoApp/AppShortcuts.xcstrings` (path via `#filePath`) · at least one key; every key contains `${applicationName}`; every key has a `de` `stringUnit` whose value contains `${applicationName}`.

### Localization and privacy (app)

67. `LocalizationTests.catalogComplete` (existing, extended) · also checks `GeoApp/GeoWidgets/Localizable.xcstrings` the same way. `LocalizationTests.noGermanSourceStrings` (existing, extended) · also scans `GeoApp/GeoWidgets/**/*.swift` and `GeoApp/Shared/**/*.swift`; adds `.navigationTitle(` is already there; adds `StatTile(` and `LockedCard(` to the scanned calls.
68. `PrivacyTests` (existing) still pass (no schema change). Plus `PrivacyTests.appGroupFilesHaveNoCoordinates` · write a snapshot to a temp dir, read the raw JSON text: no `latitude`/`longitude` substrings and no key from case 62's list.

### Spec details (fixed by the main model in T0)

- **Signatures** are the stubs from T0 (`GeoCore/Sources/GeoCore/Time/*.swift`, `GeoApp/GeoApp/Data/StoreLocation.swift`, `Timeline/Journal.swift`, `Pro/ProGate.swift`, `Shared/*.swift`, `Widgets/WidgetMapRenderer.swift`, `Widgets/WidgetSnapshotBuilder.swift`, `Intents/CountriesThisYearIntent.swift`). Tests use them as they are; a worker who needs another signature reports it instead of adding it.
- **Locales** in app tests: `Locale(identifier: "en")` / `Locale(identifier: "de")`, strings looked up via `L10n.string(_:locale:)` like Phase 1.
- **Stubs** return placeholder values (`[]`, `nil`, `0`, `false`, `.freshInstall`), never `fatalError`, so one missing feature does not crash the run.
- **Temp dirs**: `FileManager.default.temporaryDirectory/"<Suite>-<UUID>"`, removed in `defer`.

## Tasks

Status: ☐ open · ◐ in progress · ☑ done (reviewed by the main model)

| # | Task | Kind | Files | Turns green | Status |
| --- | --- | --- | --- | --- | --- |
| T0 | Stubs with final signatures; widget extension target, `Shared/` folder, entitlements, App Group, URL scheme in the project — **main model** | setup | GeoCore `Time/`, app stubs, `project.pbxproj`, entitlements | builds | ☑ |
| T1 | Write tests 1–7 | test | `DayKeyTests.swift`, `YearFilterTests.swift` | — | ☑ |
| T2 | Write tests 8–20 | test | `GapFillingTests.swift`, `HomeRegionTests.swift` | — | ☑ |
| T3 | Write tests 21–29 | test | `TripTests.swift` | — | ☑ |
| T4 | Write tests 30–36 | test | `StatisticsTests.swift`, `TimePrivacyTests.swift` | — | ☑ |
| T5 | Write tests 37–47 | test | `StoreLocationTests.swift` | — | ☑ |
| T6 | Write tests 48–58 (replace case 22) | test | `JournalTests.swift`, `ProGateTests.swift`, `ProStoreTests.swift` | — | ☑ |
| T7 | Write tests 59–68 | test | `WidgetSnapshotTests.swift`, `WidgetMapTests.swift`, `IntentTests.swift`, `LocalizationTests.swift`, `GeoAppTests.swift` (PrivacyTests) | — | ☑ |
| T8 | `DayKey`, `YearFilter` | impl | `Time/DayKey.swift`, `Time/YearFilter.swift` | 1–7 | ☑ |
| T9 | `GapFilling`, `HomeRegion` | impl | `Time/GapFilling.swift`, `Time/HomeRegion.swift` | 8–20 | ☑ |
| T10 | `TripDetector` | impl | `Time/Trips.swift` | 21–29 | ☑ |
| T11 | `Statistics` | impl | `Time/Statistics.swift` | 30–36 | ☑ |
| T12 | Store move: `StoreLocation`, `Store.makeContainer`, `Store.shared` uses it — **main model** | impl | `Data/StoreLocation.swift`, `Data/Store.swift` | 37–47 | ☑ |
| T13 | `Journal`, `ProGate`, `ProRules`, `ProFeature.timeline`, paywall copy | impl | `Timeline/Journal.swift`, `Pro/*.swift`, `Shared/ProRules.swift` | 48–58 | ☑ |
| T14 | Widget snapshot builder + map renderer + writer hook — hook into capture by **main model** | impl | `Widgets/*.swift`, `Shared/WidgetSnapshot.swift` | 59–63, 68 | ☑ |
| T15 | Widget extension UI: Counter, New places, Map, locked state, Pro check | impl | `GeoWidgets/*.swift` | manual check | ☑ |
| T16 | App Intent + App Shortcuts | impl | `Intents/*.swift`, `AppShortcuts.xcstrings` (main model) | 64–66 | ☑ |
| T17 | Map year filter menu + filtered counter/countries/cities, gated | impl | `Map/MapScreen.swift`, `Map/YearMenu.swift` | manual check | ☑ |
| T18 | Trips tab: timeline by year, trip detail, gated years | impl | `Trips/*.swift`, `RootView.swift` | manual check | ☑ |
| T19 | Statistics tab: overview tiles, detail (days per country, travel days per month chart, longest trip), year picker, gated | impl | `Statistics/*.swift`, `RootView.swift` | manual check | ☑ |
| T20 | Settings: home region (automatic / override picker) | impl | `Settings/HomeRegionView.swift`, `SettingsView.swift` | manual check | ☑ |
| T21 | Catalog sync + German for all new strings, widget catalog, shortcut phrases — **main model** | impl | `*.xcstrings` | 5, 6, 66, 67 | ☑ |
| T22 | Simulator check en/de, light/dark: map filter, trips, statistics, settings, paywall, widgets, Shortcut — **main model** | verify | — | — | ☑ |
| T23 | Optional: wave-2 languages (fr, es, it, nl, pt-BR) | impl | catalogs | 67 | — deferred (see Open items) |

## Handed back to Max (not in this phase)

- Register the App Group `group.de.max.geoapp` and the widget bundle ID `de.max.geoapp.widgets` for team QT6L26B55Z (Xcode's automatic signing does it on the first device build; simulator builds need nothing).
- Push `phase-2-time-stories` and open a PR when happy (committed, not pushed).
- Decide whether the map's year choice should be remembered across launches (it is, via `@AppStorage("mapYear")`) — easy to drop.

## Open items for later

- Wave-2 languages (fr, es, it, nl, pt-BR) deferred: four catalogs now (`Localizable` app + widget, `InfoPlist`, `AppShortcuts`) plus the store texts; draft + native review fits a separate session. Geo names for these languages already exist in the data (Phase 1, D4).
- Venice: a capture at the GeoNames center of Venice (in the lagoon) finds no country, so it records nothing (seen with the simulator test data; Verona/Florence/Rome are fine). Phase-0-style geocoding issue, not Phase 2 logic; gap closing covers such days in statistics.
- Grouped Italian/French/… regions still show local names ("Toscana", "Veneto") in English (Phase 1 open item), now also visible in the home region list.
- The locked state of the New places/Map widgets was not seen on screen (the simulator had a Pro test purchase by then); logic is `kind == .counter || isPro` with the same `ProRules` as the app (case 58). Running the Shortcut from Spotlight showed no dialog in the simulator; the intent is registered (Spotlight top hit) and its logic is tested (cases 64–66).
- Trips use the current home region for all history (D5); someone who moved gets old "trips" around their former home until they set the override.
- `Journal.make` runs on each body evaluation of Trips, Statistics and Settings; fine for a year or two of data, cache it if it shows up in Instruments.

## Notes

- T0: widget target `GeoWidgets` (`de.max.geoapp.widgets`, app extension, embedded via "Embed Foundation Extensions"), synchronized folders `GeoApp/GeoWidgets` (Info.plist and entitlements excluded from membership) and `GeoApp/Shared` (member of app and widget). Entitlements `GeoApp/GeoApp.entitlements`, `GeoApp/GeoWidgets/GeoWidgets.entitlements` with `group.de.max.geoapp`; simulator builds embed them (`__entitlements` section). URL scheme `geoapp` in `Info.plist`. `EntitlementFact` and the Pro rule moved to `Shared/ProRules.swift`; `ProStore.isPro(facts:now:)` delegates. Shared types are `nonisolated` because the app target defaults to MainActor and the widget target does not.
- T1–T4 reviewed: 36 core cases, all compile; new tests fail on stub values, `emptyStaysEmpty`, `capturedDaysAreNeverDuplicated`, `trailingGapRespectsMax`, `dayTripIsNoTrip` and `valueTypesHaveNoCoordinates` pass already as guards. Main model made `sortedAndEmpty` feed reversed input.

- T5–T7 reviewed: 32 app cases. Main model corrected case 49 (with home = IT-VEN the Munich day 20260513 is a second, ongoing trip → 2 trips; the spec said one).
- **xcodebuild hang:** after any failing test Xcode 27 runs `simctl diagnose` (10 min timeout). Always pass `-collect-test-diagnostics never`. Filter output with `grep -E "^✘ Test|Test run with|\*\* TEST|error:"` (without `-quiet`).
- T8 (DayKey, YearFilter) done by the main model to unblock T9–T11. T9–T11 by workers; full core suite 89/89.
- T12: `Store.shared` → `Store.makeContainer(legacy: StoreLocation.legacyURL, group: AppGroup.containerURL)`. Known edge case: if the App Group became unavailable *after* a successful move, the app would start a fresh store at the legacy URL, and when the group returns that legacy store is deleted as a leftover. Only possible if the entitlement disappears from a shipped build; accepted.
- T13: `Journal` written by the main model (needs core); Pro part by a worker (15/16, case 57 waits for the catalog merge).
- T14: snapshot builder, map renderer (equirectangular, lat 84…−58), `WidgetSync` (main model) writes snapshot + both PNGs; skipped for in-memory stores so tests never touch the real App Group. Hooks: after a new place (`LocationService`), app to background (`RootView`), `Deletion.*`, `MockData.enable`. `geoapp://pro` opens the paywall (`RootView.onOpenURL`).
- T15–T20 by workers, reviewed (builds, gating consistent: map/trips/statistics/widgets all go through `ProGate`/`WidgetKind.free`). Worker choices kept: Statistics and Trips fall back to the current year when Pro lapses; the map keeps "All years"; `TripRow` takes the selected year to decide whether dates show a year.
- T21: catalogs synced from arm64 `.stringsdata` (app + widget), 43 + 14 keys with German, plurals for `%lld days`, `%@ and %lld more`, the Shortcut answer (`Du warst %2$@ in %1$lld Ländern.`) and the widget counts. The three paywall feature lines are `manual` keys (built from `PaywallView.featureKeys`, not extractable). Removed the stale "Pro adds upcoming features …" key. The widget line "x countries · y cities" is two plural strings (one key could not pluralise both numbers). `AppShortcuts.xcstrings` holds the three phrases.
- Test state after T21 (Oct 19): GeoCore 89/89, app 78/78.
- Disk: parallel derived-data folders filled the disk (≈ 0.2 GB free at one point). Workers' folders are deleted after review; keep at most 3 parallel app builds.
- T22 simulator check (iPhone 17, Oct 19), with demo trips from the DEBUG launch argument `-enableMockTrips YES` (`MockData.enableTrips`, recorded as `.demo` through the normal recorder, removed with the test-data switch): map year menu (All years / This year / locked 2025) and filtered counter; Trips list and detail; Statistics overview, locked card, and after a StoreKit test purchase the full detail (days per country, chart, longest trip, new places); Settings home region + picker; paywall copy; Counter, New places and Map widgets on the Home Screen with live snapshot data, light and dark; Shortcut in Spotlight. English and German, light and dark.
- T22 fixes by the main model: year menus in Trips/Statistics showed only an icon (now the year as text); statistics tiles had uneven heights; German month labels were truncated (now single letters, bars fixed width); paywall feature icons aligned; widget accent color was system blue (widget asset catalog + `Color("AccentColor")`); Counter number got its unit ("4 countries"); New places line font bound to the last `Text` only; small Map widget letterboxed and lost its caption.
- Real store move seen on the simulator: the Phase 1 store (visits from Oct 18–19) was copied to `<group>/Library/Application Support/GeoApp.store` and the legacy file removed. Between T0 and T12 dev builds with the entitlement but the old default configuration created a stray `default.store` inside the group container (SwiftData's default URL moves into the App Group once the entitlement exists). Shipped code always passes an explicit URL; only dev simulators can have that leftover.
- `ProPurchaseTests` failed once on a freshly reinstalled simulator (products not loaded yet) and passed on the rerun.
- Final test state: GeoCore 89/89, app 78/78 (Oct 19, 2026).
- Simulators for parallel runs: iPhone 17 `D29B4CBB-8602-45F3-9A94-15D3064A0C2C`, iPhone 17e `14D073FF-7388-4120-AF93-AAD966FE1708`, iPhone Air `B03C1D79-51C5-4467-842C-AEC39B5977A3`, iPhone 18 Pro `388766A2-D3AC-420E-B1DE-D881509AFB56`. UI-only tasks build with `-destination 'generic/platform=iOS Simulator'`. Own `-derivedDataPath` per worker (`/tmp/geoapp-dd-<task>`). `-quiet` hides results; grep `Failing tests:` with `-A30` and ignore `error: the following command failed with exit code 0`.
