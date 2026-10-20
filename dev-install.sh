#!/bin/bash
set -euo pipefail

# Dev reinstall: stop running Roocast, build + install to /Applications, launch it.
# Usage: ./dev-install.sh [--no-launch]

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

APP_NAME="Roocast"
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
    <string>com.roocast.app</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

# Explicit adhoc sign with stable identifier (linker-signed alone is flaky with TCC).
if codesign --force --deep --sign - --identifier "com.roocast.app" "${INSTALL_PATH}" 2>/dev/null; then
    echo "   Signed adhoc as com.roocast.app"
else
    echo "   ⚠️  codesign failed — Accessibility may need a manual toggle after install." >&2
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
