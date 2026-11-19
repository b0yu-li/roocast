#!/bin/bash
set -euo pipefail

# Build a notarized, stapled Developer ID DMG for distribution (R2 + Homebrew tap).
# Usage:
#   ./Scripts/release.sh
#   ./Scripts/release.sh --skip-notarize   # local sign + DMG only (no Apple upload)
#
# Prerequisites:
#   - Developer ID Application identity in Keychain
#   - notarytool keychain profile "roocast-notary" (see ship plan §1)
# Override identity: ROOCAST_SIGN_IDENTITY="<hash-or-name>"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

APP_NAME="Roocast"
BUNDLE_ID="com.example.roocast"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_NAME="${APP_NAME}.app"
ENTITLEMENTS="Scripts/Roocast.entitlements"
NOTARY_PROFILE="${ROOCAST_NOTARY_PROFILE:-roocast-notary}"
SKIP_NOTARIZE=0

for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        -h|--help)
            echo "Usage: ./Scripts/release.sh [--skip-notarize]"
            echo "  Builds, Developer-ID-signs, packages a DMG, notarizes + staples (unless --skip-notarize)."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

VERSION=$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("Sources/Roocast/Version.swift").read_text()
major = re.search(r"static let major = (\d+)", text).group(1)
minor = re.search(r"static let minor = (\d+)", text).group(1)
patch = re.search(r"static let patch = (\d+)", text).group(1)
print(f"{major}.{minor}.{patch}")
PY
)

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_PATH="${DIST_DIR}/${BUNDLE_NAME}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGE_DIR="${DIST_DIR}/dmg-stage"

pick_developer_id() {
    if [ -n "${ROOCAST_SIGN_IDENTITY:-}" ]; then
        printf '%s\n' "${ROOCAST_SIGN_IDENTITY}"
        return
    fi
    local identities hash
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    hash="$(printf '%s\n' "${identities}" | awk '
        /Developer ID Application/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[A-F0-9]{40}$/) { print $i; exit }
            }
        }
    ')"
    printf '%s\n' "${hash}"
}

IDENTITY="$(pick_developer_id)"
if [ -z "${IDENTITY}" ]; then
    echo "❌ No Developer ID Application identity found." >&2
    echo "   Create one in Apple Developer → Certificates, then re-run." >&2
    exit 1
fi
IDENTITY_LABEL="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -v id="${IDENTITY}" 'index($0, id) { if (match($0, /"[^"]+"/)) print substr($0, RSTART+1, RLENGTH-2); exit }')"

echo "🔨 Building ${APP_NAME} ${VERSION} (release)..."
swift build -c release

echo "📦 Assembling ${BUNDLE_NAME}..."
rm -rf "${DIST_DIR}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"

ICNS_SRC="Sources/Roocast/Resources/AppIcon.icns"
if [ -f "${ICNS_SRC}" ]; then
    cp "${ICNS_SRC}" "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_PATH}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔏 Signing with ${IDENTITY_LABEL:-$IDENTITY} (hardened runtime)..."
codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${IDENTITY}" \
    --identifier "${BUNDLE_ID}" \
    "${APP_PATH}/Contents/MacOS/${APP_NAME}"

codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${IDENTITY}" \
    --identifier "${BUNDLE_ID}" \
    "${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dv --verbose=2 "${APP_PATH}" 2>&1 | awk '/Authority=|TeamIdentifier=|Identifier=|flags=/{print "   "$0}'

echo "💿 Creating ${DMG_NAME}..."
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/${BUNDLE_NAME}"
ln -s /Applications "${STAGE_DIR}/Applications"

# UDZO = zlib-compressed read-only DMG suitable for distribution.
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"
rm -rf "${STAGE_DIR}"

if [ "${SKIP_NOTARIZE}" -eq 1 ]; then
    echo "⏭️  Skipping notarization (--skip-notarize)."
else
    echo "☁️  Submitting ${DMG_NAME} to Apple notary service (profile: ${NOTARY_PROFILE})..."
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
fi

shasum -a 256 "${DMG_PATH}" | tee "${DMG_PATH}.sha256"

echo "✅ Release ready:"
echo "   ${DMG_PATH}"
echo "   ${DMG_PATH}.sha256"
if [ "${SKIP_NOTARIZE}" -eq 0 ]; then
    echo "   Gatekeeper: notarized + stapled"
fi
echo "ℹ️  After install, re-grant Accessibility once (new bundle id ${BUNDLE_ID})."
