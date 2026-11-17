# Backlog

Deferred work. Not in the shipping command list until proven on a real install.

## Toggle System Appearance

**Goal:** Built-in command (Tinycast-style) — type `dark` / `light` / `toggle appearance` → flip macOS light/dark.

**Reference:** `reference/tinycast/Tinycast/Features/SystemActions/` — `toggleAppearance` via System Events AppleScript:

```applescript
tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
```

**Tried (2026-11-17) — did not ship:**

1. **System Events AppleScript** — needs Automation TCC. Adhoc-signed `LSUIElement` Roocast got `AEDeterminePermission status=-600`, then `-1743`. Automation Settings has **no “+”**; the app never appeared under Ghostty’s entry.
2. **Global prefs write** (`AppleInterfaceStyle` + `AppleInterfaceThemeChangedNotification`) — no Automation grant, but did not flip the system theme in practice on this Mac.

**Likely next paths when revisiting:**

- Stable code-signing identity (not adhoc) so Automation prompts/TCC stick, *or*
- Private/SPI appearance APIs if still viable on the min macOS, *or*
- Confirm prefs write + notification sequence against a known-good CLI (`dark-mode`, etc.) with logging before/after `defaults read -g AppleInterfaceStyle`.

**Do not re-expose in search until a logged toggle succeeds end-to-end.**
