# Roocast distribution

**Open-source freeware** (MIT). Notarized DMG + personal Homebrew tap. Not Mac App Store. No Sparkle / in-app update yet.

Operator secrets (Team ID, notary key paths, CF login, product-site URLs) live in **`docs/DISTRIBUTION.private.md`** on the maintainer machine only — that file is gitignored. **Do not** put product-site hostnames in this public doc or in the Homebrew tap README.

## Identity (public)

| Item | Value |
| --- | --- |
| Bundle ID | `com.roobystudio.roocast` |
| Signing (release) | Developer ID Application + hardened runtime + notarization |
| Signing (local `./dev-install.sh`) | Prefer Apple Development (stable Accessibility TCC) |
| Min macOS | 14 Sonoma |

Legacy clipboard Keychain service `com.roocast.app.clipboard` is intentionally unchanged for history migration.

## Release build

```bash
./Scripts/release.sh              # sign + DMG + notarize + staple + sha256
./Scripts/release.sh --skip-notarize
```

- Entitlements: `Scripts/Roocast.entitlements`
- Output: `dist/Roocast-$VERSION.dmg` (+ `.sha256`); `dist/` is gitignored
- First public build: **0.11.0** (notarized + stapled)

## Public surfaces (GitHub-facing)

| What | URL |
| --- | --- |
| Source | https://github.com/b0yu-li/roocast |
| Homebrew tap | https://github.com/b0yu-li/homebrew-roocast |

```bash
brew tap b0yu-li/roocast
brew trust b0yu-li/roocast   # Homebrew 7+ third-party taps (once)
brew install --cask roocast
```

Cask `url` points at the public R2 object host (not a product-site domain). Product landing and custom download hostnames stay in `DISTRIBUTION.private.md` / the site repo only.

## Full release checklist

1. Bump `Sources/Roocast/Version.swift`
2. `./Scripts/release.sh`
3. Upload DMG (+ sha256) to R2 bucket `roocast-releases`
4. Bump `version` + `sha256` in `homebrew-roocast` `Casks/roocast.rb` → push (keep cask `url` on the R2 public host; homepage → this GitHub repo)
5. Bump product site (separate, non-GitHub deploy) — see private notes
6. Smoke `brew fetch --cask b0yu-li/roocast/roocast`

## Decisions

- Channel: notarized DMG + personal tap; official homebrew-cask PR later (`docs/BACKLOG.md`)
- License: **MIT** (this repo) + free binaries
- Source is public; notary credentials, CF billing, and product-site hostnames stay private / off GitHub

## Backlog (distribution)

- Official `homebrew/homebrew-cask` PR
- Optional: disable `*.r2.dev` once a custom download domain is the sole production path (custom domain must not appear on GitHub until intentional)
- Optional: registrar transfer for the product domain (private notes)
- In-app “check for updates”
