#!/usr/bin/env bash
set -euo pipefail

# Build script for macOS release and DMG packaging
echo "==> Building Flutter macOS (Release)..."
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_NAME="${BUILD_NAME:-1.0.0}"
APP_NAME="${APP_NAME:-Runner}"

flutter build macos --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  # Fallback to search for any .app in Release
  APP_PATH=$(find build/macos/Build/Products/Release -name "*.app" -depth 1 | head -n 1)
fi

echo "==> Found macOS App bundle: $APP_PATH"

OUTPUT_DMG="build/macos/Build/Products/Release/${APP_NAME}-v${BUILD_NAME}.dmg"
if command -v create-dmg &>/dev/null; then
  echo "==> Packaging DMG using create-dmg..."
  create-dmg \
    --volname "${APP_NAME} Installer" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 120 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 425 120 \
    "$OUTPUT_DMG" \
    "$APP_PATH" || true
  echo "==> DMG successfully packaged at: $OUTPUT_DMG"
else
  echo "==> create-dmg not installed, creating standard compressed DMG..."
  hdiutil create -volname "${APP_NAME}" -srcfolder "$APP_PATH" -ov -format UDZO "$OUTPUT_DMG"
  echo "==> DMG created at: $OUTPUT_DMG"
fi
