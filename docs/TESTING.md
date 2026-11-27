# Testing strategy

How Roocast decides what to test, how to write those tests, and what stays manual.

Agents: follow this doc together with [`AGENTS.md`](../AGENTS.md) rule **12** (concrete ACs → TDD → wire UI).

---

## Goals

1. **Protect behavior that users rely on** — search ranking, command lock-in, countdown parse/layout/drag math, update signing, clipboard store rules.
2. **Keep the feedback loop fast** — prefer pure Swift modules and XCTest; avoid AppKit/SwiftUI in the unit suite unless unavoidable.
3. **Encode ACs in tests** — when acceptance criteria exist, tests name and assert them; green means the AC is met for the extractable rule.
4. **Stay within the performance mission** — tests must not encourage heavyweight harnesses, network, or third-party test frameworks.

---

## Pyramid (what we invest in)

```text
        ┌─────────────────┐
        │ Manual smoke    │  Panels, Accessibility, notarized DMG, TCC
        ├─────────────────┤
        │ Integration     │  Core user paths: 2+ modules in-process
        ├─────────────────┤
        │ Unit (majority) │  Pure enums/structs: parse, score, layout, crypto
        └─────────────────┘
```

| Layer | Where | Examples |
| --- | --- | --- |
| **Unit** | Focused pure suites | `Countdown.parse` / `CommandLock.uniqueCompletion`, `IntentionScore`, `UsageRanking`, `CountdownIslandLayout` / `Drag`, `Calculator.evaluate`, `UpdateSigning.verify`, `PanelFocusPolicy`, `LaunchHandoffPlan`, `ClipboardImagePolicy`, `ActionsMenuPlacement`, `WindowSnap` frame math alone |
| **Integration** | Same XCTest target; compose ≥2 modules or I/O boundary | See below — **first-class**, not “rare” |
| **Manual smoke** | Human / `./dev-install.sh` | Launcher show/hide, island hover × + drag feel, Accessibility grants, notarization, Homebrew cask fetch |

### What counts as Integration (do these here)

In-process only (no XCUITest). A test is **integration** when it crosses a seam users hit:

| Seam | Home | Asserts |
| --- | --- | --- |
| **`AppSearch.results` + stubs** | `AppSearchTests` (results/rank cases) + `CoreUserPathIntegrationTests` | Lead rows, built-in commands, folder/app ranking, demote sink, empty-query switch suggestions — real `AppSearch` + `AppItem.stub` / folders |
| **Store round-trips** | `ClipboardStoreTests` (persist/reload) + clipboard cases in `CoreUserPathIntegrationTests` | Prepend / recopy / remove → `persistNow` → new store `loadPersistedHistory` → same order/content; image soft-cap + owned blobs when applicable |
| **Session / index seams** | `CoreUserPathIntegrationTests` | `SearchSession` lock → search lead; prefs file → demote → rank; zoxide publish → `AppIndex.search`; snap hit → `targetFrame`; signed feed → outcome |

**Unit vs integration split for search/clipboard:**

- **Unit:** `matchesQuitCommand("qui")`, `IntentionScore.score…`, `ClipboardStore.preview…` / date-bucket helpers with no disk.
- **Integration:** any `AppSearch.results(…)` with apps/folders/demote; any clipboard path that writes JSON (or blobs) and reads them back.

Prefer extending the existing suite that owns the seam (`AppSearchTests` / `ClipboardStoreTests`) for search/store composition. Use `CoreUserPathIntegrationTests` for **cross-feature** paths (session↔search, prefs↔search, index↔zoxide, search↔snap, feed pipeline).

### Health check (honest)

| Layer | Status | Notes |
| --- | --- | --- |
| **Unit** | Strong | Keep pure rules here; don’t dilute with `results()` + stub soups |
| **Integration** | Required | `AppSearch`+stubs and store round-trips **are** this layer (already largely present); also session/index/update compositions in `CoreUserPathIntegrationTests` |
| **UI / E2E** | Manual only | No XCUITest/snapshots yet — prefer pure layout modules over screenshot harnesses |

We do **not** currently run UI snapshot or XCUITest suites in CI. Prefer extracting layout/policy into pure modules (as with the countdown island) over screenshot diffs until a snapshot harness earns its keep.

### Core user paths (integration must cover)

When adding or changing these paths, add/extend integration tests (right file per table above):

1. **Launcher search** — `AppSearch.results` + stubs (rank, built-ins, folders, demote, usage/frecent)
2. **Countdown CLI** — lock chip → duration → ready lead (and unlock/clear)
3. **Search demote** — `SearchRankPreferences` → `AppSearch.results`
4. **Calculator lead** — expression beats weak app name match
5. **Window snap** — search hit kind → `WindowSnap.targetFrame` (no AX write)
6. **Zoxide** — published match → `AppIndex.search("z …")` returns folder; `zoom` is not z-mode
7. **Clipboard store** — recopy / mutate → persist → reload round-trip
8. **Updates** — decode signed feed → available / upToDate (ephemeral keys)

---

## Workflow: ACs → TDD → wire

For non-trivial UX or behavior changes:

1. **Write explicit ACs** (numbered, given/when/then). Lock ambiguous UX with the user before coding.
2. **Extract the rule** into a pure type (`enum` / `struct`, `nonisolated` where possible) under `Sources/Roocast/`.
3. **Add failing XCTest cases** that map 1:1 to ACs (comment or name: `testGrabOffsetKeepsCursorGluedAcrossMoves` ↔ AC4).
4. **Implement until green.**
5. **Wire AppKit/SwiftUI** to call the pure API. Panel code stays thin; geometry/policy stays tested.

If the change is a one-line copy tweak or pure docs, skip the ceremony. If the change is “make the pill feel right,” do not skip ACs.

---

## What must have unit tests

| Area | Pure module / entry | Must cover |
| --- | --- | --- |
| Search ranking / demote | `IntentionScore`, `UsageRanking`, `AppSearch`, `SearchRankPreferences` | Prefix vs substring, frecent/term boost, demote order, built-in commands |
| Calculator | `Calculator` | Ops, reject bare numbers / plain text |
| Command lock | `CommandLock` | Unique prefix, compose query |
| Countdown | `Countdown`, `CountdownIslandLayout`, `CountdownIslandDrag` | Parse/lead/hint, compact size, centered label, overlay badge, grab-offset invariance |
| Updates | `UpdateSigning`, `UpdateCheck` feed decode | Fail-closed missing fields; Ed25519 with ephemeral keys |
| Focus / panels (policy) | `PanelFocusPolicy` | Restore / activate rules without opening windows |
| App launch handoff | `LaunchHandoffPlan` | Dismiss before launch; no completion wait; no focus restore |
| Clipboard images | `ClipboardImagePolicy` | Finder → path pointer; paste fileURL not PNG; soft-cap owned only |
| ⌘K menu placement | `ActionsMenuPlacement` | Live viewport sizing (no const-height twitch); below/above clamp |
| Smart Ranking | `UsageRanking`, `UsageRankingStore` | Frecent/terms; scoreBoost; AppSearch 1–2 char steer; demote still sinks |
| Window snap math | `WindowSnap` (pure helpers) | Frame math where extracted |
| Zoxide / expander / toggles | parsers & path helpers | Grammar and path resolution without requiring live CLI when possible |

New feature → new or extended tests in the same PR. “We’ll test later” is not acceptable for core services.

---

## What stays manual (for now)

- Visual density / materials / Dark Mode “looks right”
- Global hotkeys and Carbon event taps
- Accessibility TCC prompts and AX window placement on real apps
- Countdown island *feel* after unit geometry is green (still smoke: hover ×, drag across screen, cancel)
- Notarized DMG Gatekeeper path, in-app update install on a real install location
- Homebrew cask `brew fetch` / livecheck against GitHub

Document smoke steps in the PR when the change touches those surfaces.

---

## Test code conventions

- **Target:** `RoocastTests` (`@testable import Roocast`).
- **Framework:** XCTest (Swift Testing may appear later; do not dual-stack casually).
- **Names:** `test<Behavior>()`; for AC-driven work, name or comment the AC.
- **Data:** stubs via `AppItem.stub`; no real disk icons required for ranking tests.
- **Identity / network:** never use production bundle IDs, Team IDs, product hosts, or real update keys. Prefer `example.com` and ephemeral Ed25519 keypairs (see AGENTS rule 11).
- **No flake:** no `sleep` for timing; no dependence on machine locale beyond what the API under test specifies.
- **Run:** from repo root with the Xcode toolchain, e.g.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --disable-sandbox
# or a filter:
swift test --filter CountdownIslandLayoutTests --disable-sandbox
```

Command Line Tools alone may fail to resolve `XCTest` — use full Xcode.

---

## Design for testability

- Prefer **value types** and **static pure functions** for rules.
- Inject services; avoid singleton god objects (AGENTS architecture).
- Keep SwiftUI/`NSPanel` as adapters: if a rule needs a test, it should not live only inside `mouseDragged`.
- When a panel must hold state, push transitions through tested helpers (`CountdownIslandDrag.origin`).

---

## CI and release gates

- Local: `swift test` before merging behavior changes; `./dev-install.sh` smoke for panel work.
- Release: `Scripts/release.sh` is not a substitute for unit tests — run the suite before cutting a version when countdown/search/update code changed.
- GitHub Actions: add a `swift test` job when CI is introduced; until then, the strategy still applies to agents and humans.

---

## Anti-patterns

- Testing implementation details of SwiftUI body structure
- Screenshot-only “tests” with no AC
- Hitting live network or R2 from unit tests
- Hardcoding shipping identity in fixtures
- Growing AppKit subclasses to be “tested” via private selectors instead of extracting policy

---

## Related docs

- [`AGENTS.md`](../AGENTS.md) — mission, performance budget, rule 12 (ACs + TDD)
- [`docs/DISTRIBUTION.md`](DISTRIBUTION.md) — release / update feed verification (manual + signed feed)
- [`docs/BACKLOG.md`](BACKLOG.md) — known gaps that may need future test coverage
