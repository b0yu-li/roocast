#!/bin/bash
set -euo pipefail

# Roocast install script
# Builds release version and installs to /Applications

APP_NAME="Roocast"
INSTALL_DIR="/Applications"
BUILD_DIR=".build/release"
BUNDLE_NAME="${APP_NAME}.app"

echo "🔨 Building ${APP_NAME} in release mode..."
swift build -c release

echo "📦 Creating app bundle..."
# Remove old bundle if exists
rm -rf "${BUILD_DIR}/${BUNDLE_NAME}"

# Create bundle structure
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources"

# Copy executable
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

# Create Info.plist
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
# Remove old installation if exists
if [ -d "${INSTALL_DIR}/${BUNDLE_NAME}" ]; then
    echo "   Removing old installation..."
    rm -rf "${INSTALL_DIR}/${BUNDLE_NAME}"
fi

# Copy to /Applications
cp -R "${BUILD_DIR}/${BUNDLE_NAME}" "${INSTALL_DIR}/"

echo "✅ ${APP_NAME} installed successfully to ${INSTALL_DIR}/${BUNDLE_NAME}"
echo ""
echo "You can now launch it from Applications or press CMD+Space (if configured)"
