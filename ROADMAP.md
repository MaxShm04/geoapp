# Roadmap: Country & City Tracker

Oct 15, 2026 · Adopted scope

**Decided:** Validation (Phase 0), Time & stories, Everywhere (sync and devices), Year in review, translation into further languages, and subscription plans.
**Not adopted for now:** Photo import, manual entry and JSON backup (from the former Phase 1), the Nomad tools (Schengen and residency day counters), and the depth features (detail packs, landmarks, globe, poster). See the end of this file.

## Where the app stands today

The prototype from the briefing is essentially complete:

| Area | Current state |
| --- | --- |
| Capture | Significant Location Changes, CLVisits and a capture on app open; filters for accuracy and flights (`VisitRules`) |
| Offline geocoding | Countries (Natural Earth), regions (admin‑1), districts for 151 countries, cities ≥ 15,000 inhabitants (GeoNames) |
| Data | `DayVisit`: one entry per place per day, with region/district, capture count and source. No raw coordinates. Versioned schema (V1 → V2) |
| Map | MapLibre without tiles: world → country → region, OSM details for 269 large cities |
| Lists & control | Countries/cities, swipe to delete, delete everything, diagnostic log, location probe |

`DayVisit` is the base for everything below: year filter, trips, statistics and the year in review are all derived from it.

---

## Timeline

```
                 2026              │ 2027
                 Oct  Nov  Dec     │ Jan  Feb  Mar  Apr  May  Jun  Jul  Aug  Sep  Oct  Nov  Dec
Phase 0  Validation      ████░             │
Phase 1  Languages & subscriptions ░████████████
Phase 2  Time & stories                         ████████████
Phase 3  Everywhere                                         ████████████████
Phase 4  Year in review 2027                                                    ██████████  ★ Dec 1
Ongoing  More languages                                 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

### Phase 0: Validate the prototype (now until early Nov 2026)

Goal: answer the briefing's question with real data before building features.

| Task | Effort |
| --- | --- |
| Finish the two-week everyday test, compare SLC vs. visits, measure battery use (target < 2 %/day) | S |
| Minimum stay (rule 5, phase 2): distinguish "passed through" from "stayed", show passed-through towns faded | M |
| Close day gaps: on days without a capture, assume the person stayed where they were last seen (needed for statistics and the year in review) | S |
| Reliability view in the diagnostic log: captures per day, days without a capture | S |

**Gate:** ≥ 90 % of the cities actually visited were captured. If not, keep working on capture first.

### Phase 1: Languages & subscriptions → App Store launch (Nov 2026 – Jan 2027)

Goal: the app can be released internationally and earns money from day one.

**Localization groundwork (German + English)**

| Task | Notes | Effort |
| --- | --- | --- |
| String Catalog (`Localizable.xcstrings`) | All UI strings are currently hard-coded in German; German becomes one language among several | M |
| Plural rules | `MapScreen.counterText` and the "1 Stadt / n Städte" texts are built by hand. Switch to catalog plurals (some languages have more than two forms) | S |
| City names in the device language | Today `build_data.py` takes only the English name from `alternateNamesV2`. Extract names for all supported languages at build time and pick by `Locale` at runtime | M |
| Region and district names | `build_regions.py` / `build_districts.py` currently prefer `name_de`. Keep all available `name_xx` fields instead | S–M |
| Country names | Already use the device language (`CountryNames`) | done |
| Info.plist permission texts | `InfoPlist.xcstrings`, so the location prompts are localized too | S |

**Subscriptions**

| Task | Notes | Effort |
| --- | --- | --- |
| StoreKit 2 integration | `Product`, `Transaction.currentEntitlements`, verification on the device, no server | M |
| Paywall screen | Calm, in the app's style; shown when a Pro feature is used, never at launch | S–M |
| "Manage subscription" & "Restore" in settings | Required by App Review | S |
| StoreKit configuration file for local testing | Test the purchase flow in the simulator | S |

**Launch requirements** (needed for subscriptions to be sold at all)

- App name, icon, App Store texts and screenshots in German and English
- Privacy label "Data Not Collected"
- Accessibility pass (VoiceOver alternative to the map: the list)
- TestFlight beta with 20–50 travelers, then launch

Pro has little content at launch. Pro could open as an "early supporter" price, or the paywall could stay hidden until Phase 2. Decide before release.

### Phase 2: Time & stories (Feb – Apr 2027)

Goal: give people reasons to open the app, without push notifications. This phase builds the main Pro content.

| Feature | Description | Effort |
| --- | --- | --- |
| Year filter on the map | "This year", "2026", "all", derived from `DayVisit.day` | S |
| Trips & timeline | Detect trips: consecutive days away from the home region, e.g. "Italy, 12–19 May, 6 cities" | M |
| Home region detection | The region with the most days over the last 90 days; can be overridden in settings | S |
| Statistics | Days per country and year, new places this year, travel days per month, longest trip | S–M |
| Widgets | Small map, counter, "new places this year". Requires moving the store into an App Group (see technical notes) | M |
| Shortcuts / App Intents | "How many countries this year?" | S |

### Phase 3: Everywhere (May – Aug 2027)

Goal: the data lives on every device and survives a lost phone.

| Feature | Description | Effort |
| --- | --- | --- |
| iCloud sync & backup | CloudKit private database via SwiftData, no server of our own. Needs schema V3 (see technical notes) | L |
| iPad layout | Map and list side by side | S–M |
| Apple Watch | Complication with the counter; no capture on the Watch | M |
| Google Timeline import | Parse a Takeout/on-device export locally. The only way to fill in the past in the adopted scope | M |

### Phase 4: Year in review (Sep – Nov 2027, release Dec 1, 2027)

Goal: the most important marketing moment of the year. The first one with a full year of data.

| Feature | Description | Effort |
| --- | --- | --- |
| Year in review | A calm card series: countries, cities, new places, longest trip, days away, the year's map | M |
| Share as image | Cards rendered locally (map via MapLibre snapshot), shared via the share sheet | S |
| Localized from day one | All cards in every supported language | S |
| Look back at earlier years | Each year with data gets its own review in the statistics | S |

Note: the 2026 review would only cover a few weeks after install. A short version ("Your first weeks") is optional for Dec 2026; the full feature launches for 2027.

### Ongoing: more languages (from Phase 2)

Once the String Catalog is in place, each language is mostly translation and review work.

| Wave | Languages | When |
| --- | --- | --- |
| 1 | German, English | Phase 1 (launch) |
| 2 | French, Spanish, Italian, Dutch, Portuguese (Brazil) | Phase 2 |
| 3 | Japanese, Korean, Chinese (Simplified), Polish, Turkish | Phase 3, order based on App Store download data by country |
| Later | Arabic, Hebrew | Needs a right-to-left layout check of map overlays and sheets |

Per language: UI strings, permission texts, App Store texts and screenshots, subscription names and the year-in-review cards. Draft translations with Claude, then a review by a native speaker (e.g. from the TestFlight group).

---

## Subscription plans

### Principles

1. **Privacy stays the product.** No ads, no analytics or ad SDKs, no data sales.
2. **The core promise is free.** Automatic capture, world map, countries, cities, regions and lists cost nothing.
3. **People pay for "more out of your data", not for "your data".** Viewing and deleting your own entries is always free.
4. **No server needed.** StoreKit 2 checks subscriptions on the device; there are no running costs per user.

### Plans (starting points, to be validated in TestFlight)

| Plan | Price | Notes |
| --- | --- | --- |
| Free | €0 | Full automatic map |
| Pro monthly | approx. €1.99/month | Low barrier to entry |
| Pro annual | approx. €12.99/year | 7-day trial; the default choice on the paywall (about 45 % cheaper than monthly) |

- Family Sharing for both plans.
- Prices with App Store regional price tiers.
- Offer codes for promotions (e.g. year in review season, gifts).

### Free vs. Pro

| Feature | Free | Pro | Phase |
| --- | :---: | :---: | :---: |
| Automatic capture, world map, countries, cities, regions, districts | ✓ | ✓ | today |
| Lists, delete, diagnostic log | ✓ | ✓ | today |
| All languages | ✓ | ✓ | 1 |
| Year filter, trips, timeline | Current year | All years | 2 |
| Statistics | Overview | Full detail, per year | 2 |
| Widgets | 1 widget | All widgets | 2 |
| Shortcuts | ✓ | ✓ | 2 |
| iCloud sync & backup | | ✓ | 3 |
| iPad | ✓ | ✓ | 3 |
| Apple Watch complication | | ✓ | 3 |
| Google Timeline import | Preview ("23 countries, 140 cities found") | Save the import | 3 |
| Year in review | Compact version, shared with the app name | Full card series, without branding, earlier years | 4 |

**Strongest paywall moments in the adopted scope:** the Timeline import preview (Phase 3) and the year in review in December (Phase 4). Until Phase 2 ships, Pro has little to offer, so plan launch pricing accordingly (see Phase 1).

---

## Technical notes

- **Localization of the data:** city names come from `tools/build_data.py` as English names only; regions and districts are built with German names (`name_de`). Both pipelines must keep all language variants, and the resources grow accordingly. Store them compressed per language or as a name table next to the IDs.
- **CloudKit + SwiftData:** CloudKit sync does not support `@Attribute(.unique)`. `Country.isoCode`, `City.geonamesId` and `DayVisit.key` rely on it today. iCloud sync therefore needs schema V3 without unique constraints, with defaults for all attributes, plus a deduplication step after each sync (`DayVisits.Entry.merge` already contains the merge logic).
- **App Group for widgets/Watch:** the SwiftData store has to move from the app container into an App Group container in Phase 2. Plan this together with schema V3 so the store only moves once, or do the move first and keep it separate from the schema change.
- **New capture source:** `CaptureSource` gets `.timelineImport` with a new bit in `sourceMask` (16). Never renumber the existing ones.
- **Statistics need gap closing** from Phase 0, otherwise days without a capture are missing from the counts and the year in review.
- **Subscriptions without a server:** `Transaction.currentEntitlements` and `Transaction.updates` are enough. Keep the Pro status in memory, no account.

---

## Not adopted for now

These ideas from the first draft are parked and can be reconsidered later:

- **Former Phase 1 features:** photo import, adding and correcting visits by hand, JSON export/import. Note: without photo import or manual entry, the map starts empty after install; Google Timeline import (Phase 3) is the only way to fill in the past.
- **Nomad tools:** Schengen 90/180 calculator, residency day counter, PDF/CSV report, threshold notifications.
- **Depth:** detail packs (small towns, more city details), places of interest (UNESCO, national parks, US states), globe view, color themes, poster and print partner.
- **Lifetime purchase:** replaced by monthly and annual subscriptions.
- **Never:** ads, tracking SDKs, accounts with our own server, social feed, badges and streaks.
