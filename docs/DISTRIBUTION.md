# Roocast distribution

**Open-source freeware** (MIT). Notarized DMG + personal Homebrew tap. Not Mac App Store. In-app **Check for Updates** is a first-party installer (no Sparkle): user-initiated only, Ed25519-signed feed, sha256 + code-signature checks, then replace-in-place.

Operator secrets and **official packaging identity** (bundle id, product-site URLs, Team ID, notary keys, update Ed25519 private/public for Info.plist stamping, CF account) live in **`docs/DISTRIBUTION.private.md`** and **`Scripts/identity.env`** on the maintainer machine only — both are gitignored. **Do not** put product-site hostnames or shipping identifiers in this public doc or in the Homebrew tap README.

## Identity (public repo)

| Item | Value |
| --- | --- |
| Bundle ID / Team ID / feed URLs | Not in git — stamped into Info.plist from `Scripts/identity.env` at package time (see `identity.env.example`) |
| Signing (release) | Developer ID Application + hardened runtime + notarization |
| Signing (local `./dev-install.sh`) | Prefer Apple Development (stable Accessibility TCC) |
| Min macOS | 14 Sonoma |

Legacy clipboard Keychain service `com.roocast.app.clipboard` is intentionally unchanged for history migration.

## Release build

```bash
cp Scripts/identity.env.example Scripts/identity.env   # once — fill official values locally
./Scripts/release.sh              # sign + DMG + notarize + staple + sha256 + feed fragment
./Scripts/release.sh --skip-notarize
```

- Entitlements: `Scripts/Roocast.entitlements`
- Output: `dist/Roocast-$VERSION.dmg` (+ `.sha256` + `Roocast-$VERSION.feed.json` when the Ed25519 private key is present); `dist/` is gitignored
- Current version: see `Sources/Roocast/Version.swift`

### Update feed signing

`release.sh` signs a canonical message with the maintainer Ed25519 **private** key (never in git):

```text
roocast-update-v1
{version}
{sha256}
{dmg_url}
```

The matching **public** key is written into the .app Info.plist (`RoocastUpdatePublicKey`) from `identity.env` — not hardcoded in Swift sources. Private key path: see `DISTRIBUTION.private.md`.

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

Cask `url` points at the public R2 object host (not a product-site domain). Product landing and custom download hostnames stay private / off GitHub.

The cask sets `auto_updates true` so Homebrew does not fight the **in-app** installer. That flag is brew jargon — it does **not** enable silent/automatic updates inside Roocast.

## Full release checklist

1. Bump `Sources/Roocast/Version.swift`
2. Ensure `Scripts/identity.env` is filled (gitignored)
3. `./Scripts/release.sh` (produces DMG, sha256, signed `feed.json` fragment)
4. Upload DMG (+ sha256) to R2 bucket `roocast-releases`
5. Bump `version` + `sha256` in `homebrew-roocast` `Casks/roocast.rb` → push (keep cask `url` on the R2 public host; homepage → this GitHub repo; keep `auto_updates true`)
6. Bump product site — `index.html` / `script.js` **and** `roocast/latest.json` with **all** fields: `version`, `dmg_url`, `sha256`, `ed25519`, `released` (copy from `dist/Roocast-$VERSION.feed.json`)
7. Smoke `brew fetch --cask b0yu-li/roocast/roocast`

## In-app updates

Launcher command **Check for Updates** (`update` / `check for updates`):

1. Reads feed URL + Ed25519 public key from this build’s Info.plist; fetches feed; verifies Ed25519 (fail closed).
2. Compares semver to `AppVersion`.
3. If newer: alert **Install Update** / **Later**. Only Install downloads the DMG, checks sha256, mounts, validates code signature + Team ID (must match the **running** app), then a post-quit helper stage/swaps the running `.app` and relaunches.

**No auto-update:** no check on launch, no background polling, no silent download.

## Decisions

- Channel: notarized DMG + personal tap; official homebrew-cask PR later (`docs/BACKLOG.md`)
- License: **MIT** (this repo) + free binaries
- Source is public; packaging identity, notary credentials, update private key, CF billing, and product-site hostnames stay private / off GitHub
- Updates: first-party gold trust (Ed25519 + sha256 + SecStaticCode), user-initiated only

## Backlog (distribution)

- Official `homebrew/homebrew-cask` PR
- Optional: disable `*.r2.dev` once a custom download domain is the sole production path (custom domain must not appear on GitHub until intentional)
- Optional: registrar transfer for the product domain (private notes)
