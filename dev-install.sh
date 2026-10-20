#!/bin/bash
set -euo pipefail

# Dev reinstall: stop running Roocast, install latest build, launch it.
# Usage: ./dev-install.sh [--no-launch]

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

APP_NAME="Roocast"
BUNDLE="${APP_NAME}.app"
INSTALL_PATH="/Applications/${BUNDLE}"
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

"${ROOT}/install.sh"

if [ "${LAUNCH}" -eq 1 ]; then
    echo "🚀 Launching ${INSTALL_PATH}..."
    open "${INSTALL_PATH}"
    sleep 0.5
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        VERSION=$(defaults read "${INSTALL_PATH}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
        echo "✅ ${APP_NAME} ${VERSION} is running (CMD+Space to toggle)."
    else
        echo "⚠️  Installed, but process did not stay up — check Console.app for crashes." >&2
        exit 1
    fi
fi
