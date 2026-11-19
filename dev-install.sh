#!/bin/bash
set -euo pipefail

# Dev reinstall: stop running Roocast, build + install to /Applications, launch it.
# Usage: ./dev-install.sh [--no-launch]

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

APP_NAME="Roocast"
BUNDLE_ID="com.example.roocast"
INSTALL_DIR="/Applications"
BUILD_DIR=".build/release"
BUNDLE_NAME="${APP_NAME}.app"
INSTALL_PATH="${INSTALL_DIR}/${BUNDLE_NAME}"
LAUNCH=1

for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
        -h|--help)
            echo "Usage: ./dev-install.sh [--no-launch]"
            echo "  Stops any running Roocast, builds + installs to /Applications, then launches."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

echo "🛑 Stopping running ${APP_NAME} (if any)..."
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    # Prefer a graceful quit so hotkeys / Carbon handlers can tear down cleanly.
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true

    # Wait briefly for a clean exit, then force-kill leftovers.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done

    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "   Force-killing remaining ${APP_NAME} process(es)..."
        pkill -x "${APP_NAME}" 2>/dev/null || true
        sleep 0.3
    fi

    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "❌ Could not stop ${APP_NAME}; aborting before overwrite." >&2
        exit 1
    fi
    echo "   Stopped."
else
    echo "   Not running."
fi

echo "🔨 Building ${APP_NAME} in release mode..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "${BUILD_DIR}/${BUNDLE_NAME}"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS/${APP_NAME}"

# App icon (Exp-Z family mark — regenerate via Scripts/generate_app_icon.py --install)
ICNS_SRC="Sources/Roocast/Resources/AppIcon.icns"
if [ -f "${ICNS_SRC}" ]; then
    cp "${ICNS_SRC}" "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources/AppIcon.icns"
fi

# Keep Info.plist version in sync with Sources/Roocast/Version.swift
VERSION=$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("Sources/Roocast/Version.swift").read_text()
major = re.search(r"static let major = (\d+)", text).group(1)
minor = re.search(r"static let minor = (\d+)", text).group(1)
patch = re.search(r"static let patch = (\d+)", text).group(1)
print(f"{major}.{minor}.{patch}")
PY
)

cat > "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Info.plist" << EOF
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

echo "📋 Installing to ${INSTALL_DIR}..."
# Prefer in-place Contents replace so the Accessibility TCC entry for
# /Applications/Roocast.app is less likely to go stale than rm -rf.
if [ -d "${INSTALL_PATH}" ]; then
    echo "   Updating existing installation in place..."
    rm -rf "${INSTALL_PATH}/Contents"
    cp -R "${BUILD_DIR}/${BUNDLE_NAME}/Contents" "${INSTALL_PATH}/Contents"
else
    cp -R "${BUILD_DIR}/${BUNDLE_NAME}" "${INSTALL_DIR}/"
fi

# Sign with a *stable* identity. TCC (Privacy → Accessibility) anchors to the
# designated requirement: adhoc → CDHash (changes every build → grant churn),
# a certificate → anchored to the cert leaf CN (grant survives rebuilds).
#
# Prefer the identity's SHA-1 hash over its common name: duplicate
# "Apple Development: …" certs make name-based codesign fail with
# "ambiguous (matches … and …)".
#
# Override: ROOCAST_SIGN_IDENTITY="<hash-or-name>" ./dev-install.sh
# Note: Apple Development certs expire yearly — renewing can churn the grant.
pick_codesign_identity() {
    if [ -n "${ROOCAST_SIGN_IDENTITY:-}" ]; then
        printf '%s\n' "${ROOCAST_SIGN_IDENTITY}"
        return
    fi
    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    # Prefer Apple Development (stable Team ID / leaf CN for Accessibility).
    # Use the SHA-1 hash column — duplicate CNs make name-based codesign ambiguous.
    local hash
    hash="$(printf '%s\n' "${identities}" | awk '
        /Apple Development/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[A-F0-9]{40}$/) { print $i; exit }
            }
        }
    ')"
    if [ -n "${hash}" ]; then
        printf '%s\n' "${hash}"
        return
    fi
    # Any other valid identity hash.
    hash="$(printf '%s\n' "${identities}" | awk '
        /^[[:space:]]*[0-9]+\)/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[A-F0-9]{40}$/) { print $i; exit }
            }
        }
    ')"
    printf '%s\n' "${hash}"
}

IDENTITY="$(pick_codesign_identity)"
IDENTITY_LABEL=""
if [ -n "${IDENTITY}" ]; then
    IDENTITY_LABEL="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -v id="${IDENTITY}" 'index($0, id) { if (match($0, /"[^"]+"/)) print substr($0, RSTART+1, RLENGTH-2); exit }')"
fi

if [ -n "${IDENTITY}" ]; then
    if codesign --force --deep --sign "${IDENTITY}" --identifier "${BUNDLE_ID}" "${INSTALL_PATH}"; then
        echo "   Signed with stable identity ${IDENTITY_LABEL:-$IDENTITY}"
        echo "   Accessibility grant survives rebuilds (one re-grant needed after switching off adhoc / bundle-id change)."
        codesign -dv --verbose=2 "${INSTALL_PATH}" 2>&1 | awk '/Authority=|TeamIdentifier=|Identifier=/{print "   "$0}'
    else
        echo "   ⚠️  Signing with ${IDENTITY_LABEL:-$IDENTITY} failed — falling back to adhoc." >&2
        codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${INSTALL_PATH}" 2>/dev/null || true
    fi
else
    echo "   ⚠️  No stable signing identity found — signing adhoc (Accessibility will need re-granting after install)." >&2
    codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${INSTALL_PATH}" 2>/dev/null || true
fi

echo "✅ ${APP_NAME} ${VERSION} installed to ${INSTALL_PATH}"
echo "ℹ️  v0.3.19+: panel is nonactivating (Ghostty keeps tab focus). Logs: ~/Library/Logs/Roocast/focus.log"

if [ "${LAUNCH}" -eq 1 ]; then
    echo "🚀 Launching ${INSTALL_PATH}..."
    open "${INSTALL_PATH}"
    sleep 0.5
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "✅ ${APP_NAME} ${VERSION} is running (CMD+Space to toggle)."
    else
        echo "⚠️  Installed, but process did not stay up — check Console.app for crashes." >&2
        exit 1
    fi
fi
