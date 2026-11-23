# shellcheck shell=bash
# Source from release.sh / dev-install.sh after ROOT is set.
# Loads Scripts/identity.env if present; otherwise leaves defaults unset.

: "${ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
IDENTITY_ENV="${IDENTITY_ENV:-${ROOT}/Scripts/identity.env}"

if [ -f "${IDENTITY_ENV}" ]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "${IDENTITY_ENV}"
    set +a
fi

# Required for packaging a runnable .app
: "${BUNDLE_ID:?Set BUNDLE_ID in Scripts/identity.env (see identity.env.example)}"
: "${UPDATE_FEED_URL:=}"
: "${UPDATE_SITE_URL:=}"
: "${UPDATE_PUBLIC_KEY_B64:=}"
: "${UPDATE_DMG_BASE:=}"
