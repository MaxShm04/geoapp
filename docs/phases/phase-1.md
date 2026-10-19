# Phase 1: Languages & subscriptions

Status: **done** (Oct 18, 2026) · nothing committed yet · Plan written Oct 18, 2026 · See `ROADMAP.md`, Phase 1

## Goal

The app can ship internationally (German + English) and sell the Pro subscription. App Store assets (name, icon, screenshots, App Store texts, privacy label, TestFlight) are **not** part of this phase. They need decisions from Max and are listed under "Handed back".

## Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | **English becomes the development language** (`developmentRegion = en`, catalog source language `en`). Code strings are rewritten in English; German goes into the catalog as a translation. | Languages without a translation (French before wave 2, …) fall back to the development language. That must be English, not German. Translators in later waves work from English. |
| D2 | One `Localizable.xcstrings` for the app, `InfoPlist.xcstrings` for the permission texts. Plurals via catalog plural variations, never via hand-written `count == 1 ? … : …`. | String Catalogs are already preferred (`LOCALIZATION_PREFERS_STRING_CATALOGS = YES`). |
| D3 | Geo names are localized at **display time** by ID (`geonamesId`, region ID). The stored `City.name` stays as a fallback; the schema does not change. | No migration needed; switching the device language changes all names immediately. |
| D4 | City names: `tools/build_data.py` writes `city_names.tsv` (`geonameid`, `lang`, `name`) only for names that differ from the English one, for languages `de, fr, es, it, nl, pt`. Region names: `regions.json.z` gets a `names` object per region (`{"de": …, "en": …}`), from Natural Earth `name_xx`. District names stay as they are (geoBoundaries has local names only). | Keeps the bundle small; wave-2 languages come for free in the data. |
| D5 | Subscriptions: group "Pro", products `de.max.geoapp.pro.monthly` (≈ €1.99) and `de.max.geoapp.pro.yearly` (≈ €12.99, 7-day free trial). Family Sharing on. Local testing with `GeoApp/Products.storekit` in a shared scheme. | Prices as in `ROADMAP.md`; real products are created in App Store Connect by Max. |
| D6 | StoreKit is Apple's system framework and the only network traffic (between iOS and Apple, not from our code). No receipt server, no account. Pro status is derived from `Transaction.currentEntitlements` on every launch and kept in memory only. | Fits "No network in the app" in `CLAUDE.md`: no servers of our own, no SDKs. |
| D7 | Phase 1 ships the subscription **infrastructure** and a Pro section in Settings. Feature gates (`ProFeature`) are introduced now but nothing core is gated. Phase 2 attaches the gates to the year filter, statistics and widgets. | Pro has little content until Phase 2 (see `ROADMAP.md`). |
| D8 | Terms of Use and Privacy Policy links are required by App Review for subscriptions. URLs are constants in `ProStore.Links` with placeholder values until Max provides real pages. | Max decides where they are hosted. |
| D9 | (added during implementation) Diagnostic log outcomes (`VisitRecorder`) are stored as stable codes (`newDay`, `sameDay:<n>`, `rejected.flight`, `noCountry`, `noLocation`, … in `Data/DiagnosticOutcome.swift`) and localized at display time in `DiagnosticLogView` via `DiagnosticOutcome.text(for:)`; older entries with German free text are shown unchanged and age out with the log retention. No schema change (`outcome` stays a `String`). Logger/`os_log` and `fatalError` messages are developer-facing and stay as they are. Two expectations in `VisitRecorderTests` changed to the codes (main model). | Log entries follow the device language; a stored text could not. |
| D10 | (added during implementation) Permission texts: English base values live in `GeoApp/Info.plist` (the keys must exist in the plist), translations in `GeoApp/GeoApp/InfoPlist.xcstrings`; the `INFOPLIST_KEY_NSLocation…` build settings are removed. | Case 7. |
| D11 | (added during implementation) T5 is split into 4 groups (RootView merged into Onboarding). T5 workers only rewrite Swift and write German translations to a per-group map; the main model then extracts all keys with `xcrun xcstringstool sync` from the build's `.stringsdata` and merges the maps into `Localizable.xcstrings`, so no two workers edit the catalog. | xcodebuild does not update catalogs; parallel catalog edits would conflict. |

## Test spec

Swift Testing. Core tests in `GeoCore/Tests/GeoCoreTests/`, app tests in `GeoApp/GeoAppTests/`. Every case lists target file · setup · input → expected result.

### Localization (app)

1. `LocalizationTests.counterSingular` · `GeoAppTests/LocalizationTests.swift` · locale `en` · `MapScreen.counterText(countries: 1, cities: 1, locale: en)` → `"1 country · 1 city"`.
2. `LocalizationTests.counterPlural` · same · `en`, (5, 12) → `"5 countries · 12 cities"`.
3. `LocalizationTests.counterGerman` · same · `de`, (1, 1) → `"1 Land · 1 Stadt"`; (5, 12) → `"5 Länder · 12 Städte"`.
4. `LocalizationTests.cityCountGerman` / `cityCountEnglish` · `ListScreen.cityCountText(_:locale:)` · 0, 1, 3 → `de`: "0 Städte", "1 Stadt", "3 Städte"; `en`: "0 cities", "1 city", "3 cities".
5. `LocalizationTests.catalogComplete` · loads `Localizable.xcstrings` from the app bundle source (path relative to `#filePath`) · every key has a `de` translation with state `translated`, none `needs_review` or missing. Fails with the list of missing keys.
6. `LocalizationTests.noGermanSourceStrings` · scans `GeoApp/GeoApp/**/*.swift` (relative to `#filePath`) · no string literal passed to `Text(`, `Label(`, `Button(`, `Section(`, `navigationTitle(`, `Toggle(`, `LabeledContent(`, `ContentUnavailableView(`, `.alert(` contains `ä ö ü ß Ä Ö Ü` · ensures D1 (English source). Comments are ignored.
7. `LocalizationTests.permissionTextsLocalized` · `InfoPlist.xcstrings` · keys `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` exist with `en` and `de` values; the English values mention that only city, country and time are stored.

### Localized geo names (core)

8. `LocalizedNameTests.cityGerman` · `GeoCoreTests/LocalizedNameTests.swift` · `GeoLookup.shared.cities.localizedName(id: <Rome 3169070>, language: "de")` → `"Rom"`.
9. `LocalizedNameTests.cityEnglishDefault` · same · Rome, `"en"` → `"Rome"`; Rome, `"xx"` (unknown language) → `"Rome"`.
10. `LocalizedNameTests.cityWithoutTranslation` · a city with no entry in `city_names.tsv` (e.g. Potsdam 2852458), `"de"` → its English name.
11. `LocalizedNameTests.cityMunichFrench` · Munich 2867714, `"fr"` → `"Munich"`; `"de"` → `"München"`; `"it"` → `"Monaco di Baviera"`.
12. `LocalizedNameTests.regionGermanEnglish` · `RegionIndex.shared.region(in: "DE", lat: 48.14, lon: 11.58)` → region; `localizedName(language: "de")` → `"Bayern"`, `"en"` → `"Bavaria"`.
13. `LocalizedNameTests.regionFallback` · same region, `"xx"` → English name.

### Subscriptions (app)

`ProStore` gets its entitlement facts through a small protocol so the logic is testable without StoreKit:

```swift
struct EntitlementFact: Sendable { let productID: String; let revoked: Bool; let expires: Date?; let isUpgraded: Bool }
```

14. `ProStoreTests.noEntitlementsMeansFree` · `GeoAppTests/ProStoreTests.swift` · facts `[]` → `ProStore.isPro(facts:now:) == false`.
15. `ProStoreTests.activeYearly` · `[pro.yearly, expires now+30d]` → `true`.
16. `ProStoreTests.expired` · `[pro.monthly, expires now-1s]` → `false`.
17. `ProStoreTests.revoked` · `[pro.yearly, revoked, expires now+30d]` → `false`.
18. `ProStoreTests.upgradedIgnored` · `[pro.monthly upgraded (expires +10d)]` only → `false`; plus `[pro.yearly +300d]` → `true`.
19. `ProStoreTests.unknownProduct` · `[com.other.product, +30d]` → `false`.
20. `ProStoreTests.productIDs` · `ProStore.productIDs == ["de.max.geoapp.pro.monthly", "de.max.geoapp.pro.yearly"]`.
21. `ProStoreTests.storekitConfigMatches` · parses `GeoApp/Products.storekit` (JSON, path via `#filePath`) · contains both product IDs, one subscription group, yearly has a 7-day free-trial introductory offer, Family Sharing enabled on both.
22. `ProStoreTests.gatesOffInPhase1` · every `ProFeature.allCases` → `ProFeature.isGated(_:)` is `false` (D7). Phase 2 changes this test deliberately.
23. `PrivacyTests` (existing) still pass: no coordinates in any model; additionally `ProStore` stores nothing in SwiftData or UserDefaults except nothing at all (`UserDefaults.standard` has no key containing `pro`/`entitlement` after `refresh(facts:)`).

### Accessibility (app)

24. `AccessibilityTests.mapSummary` · `MapScreen.accessibilitySummary(countries: 5, cities: 12, locale: en)` → `"World map. 5 countries and 12 cities visited. The list tab shows them as a list."`; `de` → German equivalent from the catalog.


### Test purchase (app)

25. `ProPurchaseTests.purchaseUnlocksPro` · `GeoAppTests/ProPurchaseTests.swift` · (added in T15 by the main model) `SKTestSession(contentsOf: GeoApp/Products.storekit)`, dialogs off, transactions cleared · `loadProducts()` → both IDs in order; yearly has a free-trial intro offer; `isPro == false` before; `purchase(yearly) == true` → `isPro == true`. An expiry check (`expireSubscription`) was tried but StoreKit's test environment did not drop the entitlement within 5 s, so it is not part of the test.

### Spec details (fixed by the main model before T1–T3)

These pin down what the cases above leave open. Test workers follow them; implementation follows the tests.

- **Locale API (cases 1–4, 24).** Signatures: `MapScreen.counterText(countries: Int, cities: Int, locale: Locale = .current) -> String`, `ListScreen.cityCountText(_ count: Int, locale: Locale = .current) -> String`, `MapScreen.accessibilitySummary(countries: Int, cities: Int, locale: Locale = .current) -> String`. Tests pass `Locale(identifier: "en")` / `Locale(identifier: "de")`. The implementation must look strings up in the catalog **for that locale's language** (e.g. via the `<lang>.lproj` bundle inside `Bundle.main`), not only format numbers with it; a shared helper `L10n.string(_:locale:)` lives in `GeoApp/GeoApp/Localization/L10n.swift` (T6).
- **Case 24 German:** `"Weltkarte. 5 Länder und 12 Städte besucht. Der Tab „Liste“ zeigt sie als Liste."`. Singular in both languages too: (1, 1) en → `"World map. 1 country and 1 city visited. The list tab shows them as a list."`.
- **Case 5:** catalog at `GeoApp/GeoApp/Localizable.xcstrings`. Keys with `"shouldTranslate": false` are skipped. A key passes when `localizations.de` exists and either `stringUnit.state == "translated"` or it has `variations` (plural) whose every `stringUnit.state == "translated"`. Missing file → the test fails with a clear message (no crash).
- **Case 6:** scans every `*.swift` under `GeoApp/GeoApp/`, strips `//` line comments and `/* */` block comments, then finds string literals that are the first argument of `Text(`, `Label(`, `Button(`, `Section(`, `.navigationTitle(`, `Toggle(`, `LabeledContent(`, `ContentUnavailableView(`, `.alert(`, `.confirmationDialog(`, `hintCapsule(`. Fails with `file:line literal` for each one containing `äöüßÄÖÜ` or a German quote `„`. `Data/MockData.swift` is excluded (sample place names).
- **Case 7:** catalog at `GeoApp/GeoApp/InfoPlist.xcstrings`. Both keys have `en` and `de` `stringUnit.value`s that are non-empty and differ. The English `NSLocationAlwaysAndWhenInUseUsageDescription` contains (case-insensitive) `city`, `country` and `time`. Additionally, `project.pbxproj` contains no `INFOPLIST_KEY_NSLocation` build setting (the texts come only from the catalog).
- **Case 21:** `Products.storekit` lives at `GeoApp/Products.storekit` (next to the `.xcodeproj`, outside the synchronized app folder). JSON: exactly one entry in `subscriptionGroups`; its `subscriptions` contain both product IDs; every subscription has `familyShareable == true`; the yearly one has `introductoryOffer.paymentMode == "free"` and `introductoryOffer.subscriptionPeriod` of `"P1W"` or `"P7D"`. Also: `GeoApp.xcscheme` contains a `StoreKitConfigurationFileReference` whose identifier ends in `Products.storekit`.
- **ProStore API (cases 14–23).** In `GeoApp/GeoApp/Pro/ProStore.swift`: `struct EntitlementFact: Sendable { let productID: String; let revoked: Bool; let expires: Date?; let isUpgraded: Bool }` (memberwise init); `@MainActor @Observable final class ProStore` with `static let productIDs: [String]`, `static func isPro(facts: [EntitlementFact], now: Date) -> Bool`, `private(set) var isPro: Bool`, `init()` (starts nothing), `func refresh(facts: [EntitlementFact], now: Date = .now)`, `func start()` (StoreKit listener + first refresh, called by the app only). `enum ProFeature: String, CaseIterable { case yearFilter, statistics, widgets }` with `static func isGated(_ feature: ProFeature) -> Bool`. `expires == nil` and not revoked/upgraded counts as active.
- **Case 23:** a test in `ProStoreTests.swift`: snapshot `UserDefaults.standard.dictionaryRepresentation().keys`, call `refresh(facts:)` with an active yearly fact, assert no *new* key contains `pro` or `entitlement` (case-insensitive) and `isPro == true`; and `Store.schema.entities` has no entity whose name contains `Pro` or `Entitlement`.
- **Stubs** written by test workers return placeholder values (`""`, `false`, `[]`) instead of `fatalError`, so one missing feature does not crash the whole test run.

## Tasks

Status: ☐ open · ◐ in progress · ☑ done (reviewed by the main model)

| # | Task | Kind | Files | Turns green | Status |
| --- | --- | --- | --- | --- | --- |
| T1 | Write tests 1–7, 24 (with minimal stubs: `counterText(…, locale:)`, `cityCountText`, `accessibilitySummary`) | test | `GeoAppTests/LocalizationTests.swift`, `GeoAppTests/AccessibilityTests.swift` | — | ☑ |
| T2 | Write tests 8–13 (stubs: `CityIndex.localizedName`, `Region.localizedName`) | test | `GeoCoreTests/LocalizedNameTests.swift` | — | ☑ |
| T3 | Write tests 14–23 (stubs: `ProStore`, `EntitlementFact`, `ProFeature`) | test | `GeoAppTests/ProStoreTests.swift` | — | ☑ |
| T4 | Switch development language to `en` (pbxproj `developmentRegion`, catalog source) — **main model** | impl | `project.pbxproj` | — | ☑ |
| T5 | Rewrite UI strings in English and create `Localizable.xcstrings` with German translations, one worker per screen group (Onboarding · Map+CountrySheet · List · Settings+Diagnostics+Licenses · RootView) | impl | per group | 5, 6 | ☑ |
| T6 | Plural-aware `counterText`, `cityCountText`, region/city counts in `CountrySheet` | impl | `MapScreen.swift`, `ListScreen.swift`, `CountrySheet.swift`, catalog | 1–4 | ☑ |
| T7 | `InfoPlist.xcstrings` with both permission texts in `en`/`de`; remove `INFOPLIST_KEY_NS…` German literals from build settings — **main model** (touches permissions) | impl | `InfoPlist.xcstrings`, `project.pbxproj` | 7 | ☑ |
| T8 | `build_data.py`: write `city_names.tsv`; `build_regions.py`: keep `name_xx` per region; rebuild data | impl | `tools/*.py`, Resources | — | ☑ |
| T9 | `CityIndex` loads `city_names.tsv` lazily; `localizedName(id:language:)`; `Region.localizedName(language:)` | impl | `CityIndex.swift`, `RegionIndex.swift` | 8–13 | ☑ |
| T10 | Use localized names in the UI: `VisitRow` callers, `CountrySheet`, `DiagnosticLogView`, city pins | impl | those views, `CountryFocus.swift` | manual check | ☑ |
| T11 | `ProStore` (@Observable): products, `isPro(facts:now:)`, `refresh()`, `Transaction.updates` listener, purchase, restore (`AppStore.sync()`); `ProFeature` enum | impl | `GeoApp/Pro/ProStore.swift` | 14–20, 22, 23 | ☑ |
| T12 | `Products.storekit` + shared scheme `GeoApp.xcscheme` referencing it | impl | `GeoApp/Products.storekit`, `xcshareddata/xcschemes/GeoApp.xcscheme` | 21 | ☑ |
| T13 | Paywall view (calm, app style; both plans, trial note, restore, Terms/Privacy links) and Settings "Pro" section (status, upgrade, manage via `manageSubscriptionsSheet`, restore) | impl | `GeoApp/Pro/PaywallView.swift`, `SettingsView.swift` | manual check | ☑ |
| T14 | Accessibility: map summary label + hint, `accessibilityElement` for the counter, VoiceOver order in onboarding, Dynamic Type check at XXL | impl | `MapScreen.swift`, `OnboardingView.swift` | 24 | ☑ |
| T15 | Simulator check in `en` and `de`, light/dark, purchase flow with the StoreKit config — **main model** | verify | — | — | ☑ |

## Handed back to Max (not in this phase)

- App name (still open in the briefing) and `CFBundleDisplayName`
- App icon (currently empty)
- App Store texts and screenshots (de, en), privacy label "Data Not Collected"
- Creating the subscription products in App Store Connect with the IDs from D5
- URLs for Terms of Use and Privacy Policy (D8)
- TestFlight beta

## Notes

- Worker builds: use `-destination 'id=<udid>'` (name-based destinations hung in `simctl diagnose`), one simulator per parallel test run (iPhone 17 `D29B4CBB-8602-45F3-9A94-15D3064A0C2C`, iPhone 17e `14D073FF-7388-4120-AF93-AAD966FE1708`), own `-derivedDataPath` per worker. `-quiet` hides the results; grep for `Failing tests:` with `-A30`, and ignore the spurious `error: the following command failed with exit code 0`.

- T8: `city_names.tsv` has 8016 rows (169 KB). Grouped regions (FR, IT, ES, JP, SI, GB: groups of admin-1 units) only carry an `en` name, so they show their current name in every language; wave 2 needs a per-group naming rule. `build_data.py` runs `build_regions`/`build_districts` itself (≈ 40 min, mostly districts). The rebuild changed `data_version.txt`, so `CityRemapping` runs once on the next app start.
- T9: `city_names.tsv` is loaded lazily on the first `localizedName` call (file-private global), never by `GeoLookup.shared`.
- T11: `ProStore.start()` runs from a `.task` on the root view in `GeoAppApp`. Terms link = Apple standard EULA, privacy link = placeholder (D8).
- T12: scheme references `../../Products.storekit` (relative to `GeoApp.xcodeproj/xcshareddata`). Storefront DEU, prices €1.99 / €12.99.
- T10: city/region names are localized via `Location/PlaceNames.swift` (language = `Locale.current`, same as `CountryNames`). `DiagnosticEntry` stores only a city name without ID, so the diagnostic log keeps the stored name (no schema change, D3).
- T13: the paywall uses StoreKit's `SubscriptionStoreView(productIDs:)` (system-localized prices, trial note, renewal text, restore button, Terms/Privacy via `subscriptionStorePolicyDestination`) instead of a hand-built plan list. The Pro section is the first section in Settings.
- T14: the world map is hidden from VoiceOver while no country is selected; a transparent overlay element carries the summary label and hint (a conditional label on the map itself would recreate the MapLibre view).
- Test state after T14: GeoCore 53/53, app 47/47 (Oct 18, 2026).
- T15 (simulator check, iPhone 17, Oct 18): onboarding, map, country sheet, list, settings and paywall checked in English and German, light and dark, and at Dynamic Type XXL. Seen working: plural counters ("1 country · 1 city", "3 Länder · 3 Städte"), localized city/region names ("Rom", "München"/"Munich", "Bavaria"/"Bayern"), German dates, permission dialogs in English from `Info.plist`.
- T15 purchase: Xcode did not answer Apple events (AppleScript `run` timed out), so the app could not be started through the scheme's StoreKit config. Instead, case 25 runs `SKTestSession` with `Products.storekit`; the configuration it installs stays active in that simulator, so the app (launched via `simctl`) then showed both plans and a UI test purchase of the yearly plan worked: paywall closes, Settings shows "Active" and "Manage subscription" opens the system sheet ("Renews Oct 25, 2026" after the free week).
- T15 fixes: `Products.storekit` lacked `numberOfPeriods` in the intro offer, so StoreKit loaded no products at all (fixed). Paywall showed two close buttons (removed ours, StoreKit's `.cancellation` button stays) and truncated the body text (now wraps). German Pro footer said "Aufnahme" instead of the app's term "Erfassung". Straight apostrophes in "Let’s go" etc. replaced with typographic ones (catalog keys renamed).
- The paywall language follows the StoreKit config's `_locale` (`de_DE`) in local testing, because `SubscriptionStoreView` sets the storefront locale for its content; with real App Store products it follows the storefront.
- Catalog maintenance: after UI changes, build for one architecture and run `xcrun xcstringstool sync GeoApp/GeoApp/Localizable.xcstrings --stringsdata …` with the `.stringsdata` files from `Objects-normal/arm64` only (a generic build also leaves x86_64 files that may be stale), then add the German for new keys; `catalogComplete` lists anything missing.
- Open for later: grouped regions (FR/IT/ES/JP/SI/GB) and the diagnostic log keep untranslated names; paywall copy ("Pro adds upcoming features …") should be revisited when Phase 2 ships the features; privacy URL is a placeholder (D8).
- Final test state: GeoCore 53/53, app 48/48.
- Bug fixes from the simulator test on Oct 18, 2026 (before this phase): overseas territories split from FR/NL in the data, onboarding flash after granting "Always", city names clipped at the screen edge.
