# App Icon — locked 2026-11-18

Canonical mark: `locked.png` → installed as
`Sources/Roocast/Resources/AppIcon.png` (+ `AppIcon.icns`).

Do not casual-tweak tunables in `Scripts/generate_app_icon.py`. Bump an `iter-NN`
preview + re-lock if changing.

## Design

Same-family as Exp-Z (`sibling Exp-Z icon pipeline`):
- slate→teal dual-mode field
- cyan→lime 3D wordmark
- flat baseline + italic shear (`LETTER_TILT_DEG = -14`)
- no background objects

## Locked layout

Two-row wordmark (layout sketch):

| Row | Text | Scale | nudge_x |
| --- | ---- | ----- | ------- |
| 1 | Roo | 0.63 | 0.0 (ink-aligned with cast) |
| 2 | cast | 1.0 | 0.0 |

Other locked tunables: `FONT_SIZE = 380`, `ROW_GAP_FRAC = 0.04`, `DEPTH = 72`.

Fallback single-line **Roo**: `locked-fallback-roo.png`.

## Regenerate (should match locked)

```bash
.venv/bin/python Scripts/generate_app_icon.py --install
```
