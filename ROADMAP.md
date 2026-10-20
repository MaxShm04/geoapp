# Roadmap: Country & City Tracker

Oct 20, 2026 · Current plan

**Next, in this order:** (1) trips after a move, (2) better "stayed vs. passed through" detection with suggestions and manual entry, (3) Google Timeline import, (4) year in review, (5) rethink pricing, (6) legal, (7) name and icon.
**Not scheduled:** iCloud sync, iPad, Apple Watch, wave-3 languages (see "Later"). Ideas we decided against are at the end of this file.

## Where the app stands today

| Area | State | Since |
| --- | --- | --- |
| Capture | Significant Location Changes, CLVisits and a capture on app open; filters for accuracy and flights. Background capture can only be checked on a real iPhone | Prototype |
| Offline geocoding | Countries (Natural Earth, overseas territories split from FR/NL), regions, districts for 151 countries, cities ≥ 15,000 inhabitants (GeoNames) | Prototype, fix Oct 18 |
| Data | `DayVisit`: one entry per place per day, never coordinates. SwiftData store in the App Group (for widgets), schema V2 | Phase 2 |
| Map | World → country → region → city detail. Tap a city or area for the place view: days list and calendar, delete a place there | Phase 2 + beta-menu |
| Trips & statistics | Home region detection (overridable), trips, day-gap filling, statistics, places list (searchable) on the Trips screen | Phase 2 |
| Widgets & Shortcuts | Counter, new places, map widget; "How many countries this year?" | Phase 2 |
| Languages | English source, German, French, Spanish, Italian, Dutch, Portuguese (Brazil). The wave-2 languages are Claude drafts awaiting native review. City and region names in the device language | Phase 1 + wave 2 |
| Pro | StoreKit 2 subscriptions (monthly, yearly), paywall, gates: all years, full statistics and extra widgets are Pro. Local StoreKit config for testing | Phase 1–2 |
| Testing aids | Beta menu (Debug builds only): show/hide test controls, unlock Pro, act as not subscribed, test data | beta-menu |

Plans, decisions and test specs of the finished phases: `docs/phases/phase-1.md`, `docs/phases/phase-2.md`.

---

## Sequence

```
Now ──► 1 Trips after a move ──► 2 Stayed vs. passed through ─┐
        5 Pricing decision (can run in parallel) ─────────────┤
        6 Legal ─┬─ needed for external TestFlight ───────────┤
        7 Name + icon ┘                                        ▼
                                                   ★ Test phase (TestFlight, real trips)
                                                               │
                                          3 Google Timeline import (after test phase)
                                          4 Year in review 2027 (ready Dec 1, 2027)
```

The numbering follows Max's priorities. Steps 6 and 7 are small but block the test phase: an external TestFlight build needs an app name, an icon and a privacy policy URL. Step 5 must be decided before the products are created in App Store Connect.

---

## 1. Trips after a move

**Problem:** Trips are computed against the *current* home region for the whole history. Someone who moved from Munich to London sees their old everyday life in Munich as one long "trip" (Phase 2, open item D5).

**Plan:**
- **Home region over time** instead of a single value: detect home periods automatically, e.g. the region with the most nights in a sliding 90-day window. A new period starts when another region keeps the majority for several weeks.
- **Manual correction** in Settings: a short list "Home since …" where Max can add a move with a date or correct a detected one. The current single override becomes the first entry. Existing values are migrated.
- Trips, statistics ("days away") and the year in review use the home region that was valid *on that day*.

**Open questions:** how many weeks before a new home counts (start: 6 weeks)? How to treat long stays abroad, e.g. a 3-month semester: a move, or a long trip? Proposal: detection only suggests a move, and Max confirms it.

**Effort:** M. Logic in `GeoCore/Time/HomeRegion.swift` and `Trips.swift`, UI in `HomeRegionView`.

## 2. Stayed vs. passed through (better detection, suggestions, manual entry)

**Problem:** A single capture on a train or motorway counts the same as a week in that city. The briefing's rule 5 (minimum stay) has not been built yet.

**Signals available without storing coordinates:**

| Signal | Meaning |
| --- | --- |
| CLVisit with arrival and departure | Strongest signal for a real stay, with duration |
| `firstSeen`–`lastSeen` span and `captureCount` of a `DayVisit` | Several captures over a longer span → stayed |
| Speed at capture time (`CLLocation.speed`) | Fast single capture (e.g. > 8 m/s) → passing by train/car |
| Capture on app open | Max had the phone in hand there → likely a real visit |
| Night stay (capture late evening and next morning) | Clearly stayed |

**Plan:**
- Classify each place-day when it is recorded: **stayed**, **passed through** or **uncertain**. Store only the result (a small status field, no speed, no coordinates).
- **Passed through** places appear faded on the map and count separately ("passed through 12 towns"). They don't count as visited cities by default; a setting decides.
- **Uncertain** places go into a quiet suggestions list ("Were you in Fulda on 12 May?" → yes / no), never as push notifications.
- **Add manually:** a place (city or country only) on a day or a date range, chosen from the city list with search. New `CaptureSource` `.userAdded` (new bit in `sourceMask`, never renumber existing ones).
- Thresholds are starting values for the test phase and are tuned with real data from the diagnostic log.

**Technical note:** the status field needs **schema V3**. If iCloud sync comes later, it needs another V3-type change (no unique constraints). Plan both together if the timing allows, otherwise V3 now and V4 for sync.

**Effort:** L (classification M, suggestions UI S–M, manual entry M).

## ★ Test phase (TestFlight)

- Internal testing with Max's own devices first, then external TestFlight with 20–50 travelers (needs steps 6 and 7).
- Replaces the two-week everyday test from the briefing. **Gate:** ≥ 90 % of actually visited cities captured, battery use under 2 %/day, the classification from step 2 rarely wrong.
- Native speakers in the group review the wave-2 translations.
- Validate the prices from step 5.

## 3. Google Timeline import (after the test phase)

- Google Timeline now lives on the phone; users export it as JSON from Google Maps / Android settings. The file is parsed **locally**, every point is mapped to country and city with the existing offline lookup and discarded right away, just like live capture.
- Imported days get `CaptureSource` `.timelineImport` and run through the same classification as step 2.
- **Pro moment:** free preview ("23 countries and 140 cities found"), saving the import is Pro.
- Why after the test phase: capture and classification must be reliable first, otherwise years of history are classified wrongly.

**Effort:** M.

## 4. Year in review (not during the test phase)

- Target **Dec 1, 2027**, the first year with a full year of data. No review for 2026, since only a few weeks of data and the test phase run then.
- Calm card series: countries, cities, new places, longest trip, days away, the map of the year. Rendered locally, shared as images, in all languages.
- Free: compact version with the app name. Pro: full series, no branding, earlier years.

**Effort:** M.

## 5. Rethink pricing

Current build: monthly (≈ €1.99) and yearly (≈ €12.99, 7-day trial) subscriptions.

**Option under discussion: yearly + one-time purchase (lifetime)**

| | For | Against |
| --- | --- | --- |
| Yearly subscription | Recurring revenue, finances updates and data refreshes | Some privacy-minded users dislike subscriptions |
| One-time (lifetime) | Fits the privacy audience; no server, so no running cost per user | No recurring revenue; price must be high enough (rule of thumb: 2.5–3× yearly, e.g. €29.99–34.99) |
| Monthly | Lowest entry barrier | Little value for an app opened occasionally; makes the paywall busier |

**Recommendation:** yearly + lifetime, drop monthly. Decide before step 6/7 and before creating the products in App Store Connect.

**Technical impact:** a non-consumable product `de.max.geoapp.pro.lifetime`; `ProRules` accepts it (never expires, Family Sharing on); the paywall needs a custom layout, since `SubscriptionStoreView` only shows subscriptions; update `Products.storekit`, tests and the beta menu.

## 6. Legal

To clarify (no legal advice here; have it checked by someone qualified):
- **Privacy policy** (required by Apple even for "Data Not Collected"): what the app processes on the device, location permissions, no transfer, StoreKit via Apple. Replace the placeholder URL in `ProStore.Links`.
- **Terms of use:** Apple's standard EULA is enough to start; own terms only if needed.
- **Provider identity:** EU trader status (Digital Services Act) in App Store Connect; check whether a legal notice (Impressum) is needed for the app and its website.
- **Data licences:** GeoNames (CC BY 4.0) and OpenStreetMap (ODbL) attribution in the app (already in Licenses), Natural Earth (public domain), MapLibre (BSD). Check ODbL obligations for the derived city detail data.
- **App Store privacy label:** "Data Not Collected".

**Effort:** S (writing), plus external review.

## 7. Name and icon

- Name: short, calm, works in all seven languages, free in the App Store and as a trademark (check DPMA/EUIPO). Bundle ID `de.max.geoapp` stays; only the display name changes.
- Icon: in the app's style (flat, one accent color, map motif), light, dark and tinted variants for iOS.
- Then App Store texts and screenshots per language.

**Effort:** S–M.

---

## Later (not scheduled)

| Feature | Note |
| --- | --- |
| iCloud sync & backup | CloudKit private database, no server of our own. Needs a schema without unique constraints and deduplication after each sync (see technical notes) |
| iPad layout | Map and list side by side |
| Apple Watch | Complication with the counter, no capture on the Watch |
| Wave-3 languages | Japanese, Korean, Chinese (Simplified), Polish, Turkish, ordered by App Store download data |

---

## Pro (current state, step 5 may change the plans)

### Principles

1. **Privacy stays the product.** No ads, no analytics or ad SDKs, no data sales.
2. **The core promise is free.** Automatic capture, world map, countries, cities, regions, place view and lists cost nothing.
3. **People pay for "more out of your data", not for "your data".** Viewing, adding and deleting your own entries is always free.
4. **No server needed.** StoreKit 2 checks purchases on the device; no running costs per user.

### Free vs. Pro

| Feature | Free | Pro | State |
| --- | :---: | :---: | --- |
| Automatic capture, map, countries, cities, regions, districts, place view | ✓ | ✓ | built |
| Places list, delete, diagnostic log | ✓ | ✓ | built |
| All languages | ✓ | ✓ | built |
| Trips and timeline | Current year | All years | built |
| Statistics | Overview | Full detail, per year | built |
| Widgets | 1 widget | All widgets | built |
| Shortcuts | ✓ | ✓ | built |
| Suggestions and manual entry (step 2) | ✓ | ✓ | planned |
| Google Timeline import (step 3) | Preview | Save the import | planned |
| Year in review (step 4) | Compact, with app name | Full series, no branding, earlier years | planned |

The map has no year filter any more (removed Oct 20, 2026); it always shows all years.

---

## Technical notes

- **Schema changes:** steps 1 (home periods, if stored in SwiftData) and 2 (status field, `.userAdded`) need a new schema version with a migration stage. Never change a model without one, or existing stores no longer open.
- **CloudKit + SwiftData (later):** CloudKit does not support `@Attribute(.unique)`, which `Country.isoCode`, `City.geonamesId` and `DayVisit.key` rely on. Sync needs a schema without unique constraints, defaults for all attributes and a deduplication step after each sync (`DayVisits.Entry.merge` has the merge logic).
- **Capture sources:** next free bits in `sourceMask` for `.userAdded` and `.timelineImport`. Never renumber existing ones.
- **Known data issues:** a capture in the Venice lagoon finds no country; grouped regions in FR/IT/ES/JP/SI/GB keep their local name in every language ("Lazio").
- **Subscriptions without a server:** Pro follows StoreKit's current entitlements (no comparison with the device clock), re-checked on launch, on foreground and when the paywall or Settings appear.

---

## Decided against (for now)

- **Photo import** and **JSON export/import:** not planned. Google Timeline import (step 3) and manual entry (step 2) fill in the past.
- **Nomad tools:** Schengen 90/180 calculator, residency day counter, PDF/CSV reports.
- **Depth features:** detail packs, places of interest, globe view, color themes, poster and print partner.
- **Never:** ads, tracking SDKs, accounts with our own server, social feed, badges and streaks.
