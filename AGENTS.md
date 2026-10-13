# AGENTS.md — Roocast

> A native macOS launcher. Fast by default. Light by design.

---

## Development Rules

### NO VIBE CHECKING

**When debugging, NEVER guess or assume. ALWAYS:**
1. Add logging to see what's actually happening
2. Read the code to understand the data flow
3. Test with concrete evidence, not assumptions
4. If something doesn't work, trace it from the source

**Never say "it should work" without proof. Show the logs.**

---

## Mission

Replace Raycast with a **native macOS app** that delivers instant responsiveness while consuming fewer resources than the apps it launches. Roocast exists because a launcher should never itself be the thing slowing you down.

---

## Core Philosophy

### 1. Native Means Native

- **Swift & SwiftUI only.** No Electron, no web views, no React Native, no "native-ish" wrappers.
- We use Apple's frameworks the way Apple intends: `NSPanel` for the launcher window, `AppKit` for window management, `SwiftUI` for the UI layer, `Combine` for reactive data flow.
- We do not fight the platform. We embrace macOS conventions, system fonts, system materials, and system behaviors.

### 2. Performance Is a Feature

- **Cold launch to interactive: < 200ms.** The window must appear before the user finishes their keystroke.
- **Hot launch (cached): < 50ms.** Instant. No perceptible delay.
- **Memory ceiling: 50 MB.** Hard limit. We profile, we measure, we optimize. Every allocation is justified.
- **Zero jank.** 120fps on ProMotion displays. No dropped frames during scroll, no stuttering during search.

### 3. Less Is More

- **Focused scope.** A launcher launches things. It does not manage your calendar, your CRM, or your soul.
- **No plugin marketplace.** Extensions are built-in or not supported. Complexity is the enemy of performance.
- **No network calls for core functionality.** Everything the launcher needs lives on-device. Extensions that need the network are opt-in and async.
- **No telemetry.** We don't track you. We don't phone home. Your keystrokes are yours.

### 4. Resource Consciousness

- **Every byte matters.** We measure RSS, not just allocations. Instruments is a daily tool, not a debugging afterthought.
- **Lazy everything.** Load extensions on demand. Cache aggressively but with bounded memory. Evict proactively.
- **No background daemons.** When the launcher is dismissed, it's gone. No menubar icon, no hidden processes, no "quick launch" services running 24/7.
- **Sleep-friendly.** When macOS sleeps, we sleep. No wake-on-network, no prevent-idle assertions.

### 5. macOS Citizenship

- **Follow the HIG.** System font, system colors, system spacing. If it looks like it belongs, it belongs.
- **Respect the user's Mac.** Don't fight Dark Mode. Don't fight accessibility settings. Don't fight window management.
- **Accessibility first.** VoiceOver, keyboard navigation, Dynamic Type — not afterthoughts, not "nice to haves."
- **Sandbox-friendly.** We aim for App Store compatibility. Sandboxing is a constraint we design for, not work around.

---

## Architecture Principles

### Layered Design

```
┌─────────────────────────────────┐
│         SwiftUI Views           │  ← Thin, declarative, no business logic
├─────────────────────────────────┤
│        ViewModels (Combine)     │  ← Reactive state, search, filtering
├─────────────────────────────────┤
│         Core Services           │  ← App discovery, window mgmt, extensions
├─────────────────────────────────┤
│       System Integration        │  ← NSPanel, Accessibility, ScriptingBridge
└─────────────────────────────────┘
```

### Key Decisions

- **No singleton god objects.** Services are injected, testable, replaceable.
- **Value types over reference types** where possible. Structs are cheap to copy and impossible to retain accidentally.
- **Async/await over callbacks.** Modern Swift concurrency. No completion handler pyramids.
- **Protocol-oriented extensions.** Every extension point is a protocol. Implementations are swappable.
- **No global mutable state.** If two parts of the app need to share data, they do it through explicit channels.

---

## Performance Budget

| Metric                  | Budget    | Measurement Method        |
| ----------------------- | --------- | ------------------------- |
| Cold launch             | < 200ms   | `DYLD_PRINT_STATISTICS`   |
| Hot launch              | < 50ms    | Instruments (App Launch)  |
| Memory (idle)           | < 20 MB   | Instruments (Allocations) |
| Memory (active search)  | < 50 MB   | Instruments (Allocations) |
| Search latency (p50)    | < 5ms     | Custom signposts          |
| Search latency (p99)    | < 20ms    | Custom signposts          |
| Scroll FPS              | 120fps    | Core Animation instrument |
| Binary size             | < 10 MB   | `size` command            |

---

## Development Rules

### For AI Agents and Humans Alike

1. **Measure before you optimize.** Instruments first, opinions second.
2. **Every PR includes a memory check.** If it regresses memory by > 2MB, it needs justification.
3. **No force-unwraps in production code.** `guard let` or `??` with a sensible default.
4. **Tests are not optional.** Core services have unit tests. UI has snapshot tests.
5. **Commit messages explain why, not what.** The diff shows what.
6. **If you add a dependency, justify it.** Every SPM package is a liability. Prefer the standard library.
7. **Profile on real hardware.** Simulators lie. Test on the oldest supported Mac.
8. **Dark Mode and Light Mode are both first-class.** Test both. Always.
9. **Keyboard-first design.** Every action reachable without a mouse. This is a launcher, after all.
10. **When in doubt, do less.** Remove features before adding optimizations.

---

## What Roocast Is NOT

- Not a window manager (use Rectangle or Magnet)
- Not a clipboard manager (use Maccy or Paste)
- Not a snippet expander (use TextExpander or Espanso)
- Not a workflow automator (use Shortcuts or Keyboard Maestro)
- Not a replacement for Spotlight's file search (use HoudahSpot or find)

Roocast is a **launcher**. It launches apps, finds files, runs commands, and executes extensions. That's it. That's the whole product.

---

## Tech Stack

| Layer              | Technology                          |
| ------------------ | ----------------------------------- |
| Language           | Swift 6+ (strict concurrency)       |
| UI Framework       | SwiftUI + AppKit (NSPanel bridge)   |
| Min macOS Version  | macOS 14 Sonoma                     |
| Build System       | Xcode 16+ / Swift Package Manager   |
| Testing            | XCTest + Swift Testing              |
| CI                 | GitHub Actions                      |
| Distribution       | DMG + Homebrew Cask (target: MAS)  |

---

## Project Structure (Planned)

```
roocast/
├── AGENTS.md              ← You are here
├── Roocast.xcodeproj
├── Roocast/
│   ├── App/               ← App entry point, lifecycle
│   ├── UI/                ← SwiftUI views, materials, components
│   ├── Core/              ← Search engine, app discovery, indexing
│   ├── Extensions/        ← Extension protocol + built-in extensions
│   ├── Services/          ← Window management, hotkey, accessibility
│   └── Resources/         ← Assets, localization
├── RoocastTests/
├── RoocastUITests/
└── Packages/              ← Local SPM packages for modularity
```

---

## Getting Started

```bash
# Clone
git clone https://github.com/yourusername/roocast.git
cd roocast

# Open in Xcode
open Roocast.xcodeproj

# Build & Run
# ⌘R in Xcode, or:
xcodebuild -scheme Roocast -configuration Debug build
```

---

## License

TBD

---

*Roocast: Because your launcher shouldn't need a launcher.*
