# CLAUDE.md

Project instructions for Claude Code. Edit freely — this file is loaded at the start of every session.

## Project

iOS app that records, in the background, which countries and cities you have visited and shows them on a calm world map. Everything stays on the device.

- `GeoApp/` — the iOS app (Xcode project, `GeoAppTests/`, GPX files for simulated locations)
- `GeoCore/` — Swift package with the core logic (geocoding, visit rules, data model)
- `tools/` — Python scripts that build the offline geo data (`tools/raw/` is git-ignored, refetch with `tools/fetch_data.py`)
- `Briefing.md` — product briefing for the prototype (German)
- `ROADMAP.md` — adopted scope and phases

## Non-negotiables

- Never store raw coordinates. Map a position to city/country, then discard latitude and longitude.
- No network in the app: no accounts, servers, analytics, ad SDKs or online geocoders.
- The diagnostic log never contains coordinates.

## Working mode: orchestrator + Haiku workers

When an implementation phase starts (the plan is agreed and code is about to be written), the main model acts as the **central unit** and delegates smaller tasks to Haiku 5.5 workers at high effort.

**Tests first, before any delegation**
1. **Define (main model).** The main model writes a test spec for the phase: every test case, with its name, the target file, the setup, the input and the expected result. Edge cases and the privacy guarantees are included. This is the "what", kept short, not test code.
2. **Implement (Haiku workers).** The main model dispatches the test spec to `haiku-worker`s as *test tasks*, one test file or one group of cases each, in parallel where the files differ. Workers write only test code (plus minimal stubs/signatures if needed to compile), never production logic.
3. **Check (main model).** The main model reviews the test diffs against the spec and runs the suite: everything compiles, and the new tests fail for the right reason. Gaps or wrong assertions go back to a worker.
4. **Then implement.** Only when the full test suite for the phase exists does the main model dispatch *implementation tasks*. Each brief names the tests that task must turn green.
5. Implementation workers never edit, weaken or delete tests. If a test looks wrong, the worker reports it and the main model decides.

**The main model (orchestrator)**
- Owns the plan, the architecture decisions, the test spec and the overall picture.
- Keeps its own context lean: it writes specs and briefs and reviews diffs, while workers do the bulk of the code reading and writing.
- Splits the work into small, self-contained tasks: one file or one clearly bounded change each.
- Dispatches each task to the `haiku-worker` subagent (`.claude/agents/haiku-worker.md`, model Haiku 5.5, effort high). Independent tasks run in parallel; tasks that touch the same files run one after another.
- Writes every brief so a worker needs nothing else: goal, exact files, relevant interfaces/types, constraints from this file, and what "done" looks like (e.g. which test must pass).
- Reviews every worker result (reads the diff, runs the build/tests) before moving on. Fixes or re-dispatches when something is off.

**Keep on the main model, do not delegate**
- Architecture and data-model changes (e.g. `DayVisit` schema migrations)
- Defining the test spec and reviewing the tests workers write (see above)
- Anything touching privacy guarantees, location capture or permissions
- Cross-cutting refactors that span many files
- Debugging problems a worker could not solve after one retry

**Good worker tasks**
- Writing the test code for a group of cases from the test spec
- Implementing a single function, view or type against a given interface and its tests
- Small, mechanical edits across a known list of files
- Python data-tool tweaks with a clear input/output

Outside implementation phases (planning, discussion, research, quick one-off edits) the main model works directly.

## Build & test

Build and test output is large. Never let a full log into the context: use the quiet commands below, and report only failures.

- Core package tests (Swift Testing):
  `cd GeoCore && swift test 2>&1 | grep -E "✘|error:|Test run with" | head -40`
  (the `Test run with N tests … passed/failed` line is the summary)
  Faster for one area: `swift test --filter RegionTests 2>&1 | tail -n 15`
- App build/tests (schemes: `GeoApp`, `GeoCore`):
  `xcodebuild -quiet -project GeoApp/GeoApp.xcodeproj -scheme GeoApp -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|failed|✘" | head -40`
  `-quiet` prints only warnings and errors; no output plus exit code 0 means success.
- Data tools: `python3 -m venv tools/.venv && tools/.venv/bin/pip install -r tools/requirements.txt`

Large generated files (`tools/raw/`, `GeoCore/.build/`, the geo data in `GeoCore/Sources/GeoCore/Resources/`) are blocked from reading in `.claude/settings.json`. To check a data format, look at a few lines (`head -n 5`) instead of the whole file.

## Sessions & handoff

- **One phase per session.** Start a fresh session for each implementation phase; use `/compact` between major steps within a phase.
- **Plans live in files, not in chat.** At the start of a phase the main model writes `docs/phases/<phase>.md` with the plan, the test spec (numbered cases) and a task list with status. Worker briefs point to it ("implement cases 4–7 from `docs/phases/phase-1.md`") instead of pasting the spec.
- **Keep the file current.** After each reviewed task, tick it off and note decisions in the phase file. A new session must be able to continue from that file alone.
- **Search via subagents.** For broad codebase searches use the `Explore` agent (model: haiku) and take only its conclusion; the main model reads files itself only when it needs the exact code.
- **Lean reports.** Worker reports stay short: changed files, pass/fail, failing test names with the relevant error lines — never full logs or whole file contents.

## Conventions

<!-- Add your own: code style, naming, commit messages, language of UI strings, etc. -->
