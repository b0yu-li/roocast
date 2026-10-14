# Feature Design: Multi-Instance App Detection & Profile Support

## Problem Statement
Users run multiple instances of the same app with different profiles (e.g., Firefox with "nate" and "arenza" profiles). Currently, Roocast cannot distinguish between them, showing duplicate entries with no way to tell which is which.

## Technical Investigation

### Firefox Profile System
- **Location:** `~/Library/Application Support/Firefox/profiles.ini`
- **Format:** INI file with `[ProfileN]` sections
- **Key fields:** `Name`, `Path`, `IsRelative`, `Default`
- **Launch arg:** `-P "profile_name"` or `-profile "/full/path"`

### Running Instance Detection
From process inspection:
- Main Firefox process: `/Applications/Firefox.app/Contents/MacOS/firefox -foreground`
- Child processes show `-profile /path/to/profile` but parent doesn't
- Need to find parent PID, then check child processes for profile args

### Key Insight
The main Firefox process doesn't expose the profile in its command line. We need to:
1. Find all Firefox parent processes (not helpers)
2. Check their child processes for `-profile` args
3. Map back to profile names from `profiles.ini`

## Proposed Solution

### Phase 1: Profile Detection (v0.3.0)

**1. Profile Parser**
```swift
struct FirefoxProfile {
    let name: String
    let path: URL
    let isDefault: Bool
}

class ProfileManager {
    func detectFirefoxProfiles() -> [FirefoxProfile]
    func detectRunningProfiles() -> [String: FirefoxProfile] // bundleID -> profile
}
```

**2. Enhanced AppItem**
```swift
struct AppItem {
    let id: UUID
    let name: String
    let path: String
    let icon: NSImage?
    let isRunning: Bool
    let profile: String?  // NEW: profile name if detected
    let instanceCount: Int  // NEW: number of running instances
}
```

**3. UI Changes**
- **Subtitle:** Show profile name instead of full path when profile detected
- **Badge:** Small SF Symbol overlay on icon (e.g., `person.crop.circle` for personal, `briefcase` for work)
- **Grouping:** When multiple instances exist, show instance count badge

### Phase 2: Smart Launching (v0.3.1)

**1. Profile-Aware Launch**
```swift
func launchApp(_ app: AppItem, profile: String?) {
    if let profile = profile {
        // Launch with profile argument
        let task = Process()
        task.executableURL = URL(fileURLWithPath: app.path + "/Contents/MacOS/firefox")
        task.arguments = ["-P", profile]
        try? task.run()
    } else {
        // Standard launch
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }
}
```

**2. Bring Existing Instance to Front**
- If profile is already running, activate that window instead of launching new instance

## UI Mockup

```
┌─────────────────────────────────────────────────────────────┐
│   Search apps, files, commands…                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────  │
│  │ [🦊●] Firefox (nate)                    [running]    │  │
│  │      ~/Library/.../Profiles/nate                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ [🦊●] Firefox (arenza)                  [running]    │  │
│  │      ~/Library/.../Profiles/arenza                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ──────────────────────────────────────────────────────┐  │
│  │ [🦊 ] Firefox (default)                              │  │
│  │      /Applications/Firefox.app                       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Legend:**
- `🦊●` = Firefox icon with running indicator dot
- `(nate)` = profile name in subtitle
- `[running]` = optional badge showing instance count

## Design Decisions (FINAL)

### Q1: How to detect which profile is running?
**Decision: Hybrid approach**
- Try lock files first (fast path)
- Fall back to process scanning (reliable)
- Most robust solution

### Q2: How to display multiple instances?
**Decision: Separate rows**
- Each instance gets its own row
- Profile name in subtitle
- Clear and explicit
- Easy to select specific instance

### Q3: Badge design for profiles?
**Decision: Text only**
- Profile name in subtitle
- Accessible and clear
- No visual clutter

### Q4: Scope
**Decision: Firefox only (v0.3.0)**
- Ship fast, iterate
- Can extend to Chrome later

### Q5: Searchability (NEW)
**Decision: Profile names are searchable**
- Searching "arenza" shows Firefox (arenza)
- Searching "nate" shows Firefox (nate)
- Profile name included in search index

## Implementation Plan

### Sprint 1: Profile Detection
1. Create `ProfileManager.swift`
2. Parse Firefox `profiles.ini`
3. Detect running instances
4. Map instances to profiles

### Sprint 2: UI Integration
1. Update `AppItem` with profile field
2. Update `AppIndex` to populate profile info
3. Update `AppRow` to show profile name
4. Add profile badge overlay (optional)

### Sprint 3: Smart Launching
1. Update launch logic to support `-P` argument
2. Detect existing instances and activate
3. Handle edge cases (profile not found, etc.)

## Success Criteria
- [ ] Firefox profiles are detected and shown in search results
- [ ] Profile names are displayed clearly in UI
- [ ] Profile names are searchable (searching "arenza" shows Firefox arenza)
- [ ] Launching a profile opens the correct instance
- [ ] Running profiles are indicated
- [ ] No performance regression (< 5ms search latency)

## Future Enhancements
- Chrome profile support
- Safari profile support (when available)
- Custom profile badges/colors
- Profile-specific search scopes
- Cross-app profile groups (e.g., "Work" group: Firefox-work + Chrome-work)
