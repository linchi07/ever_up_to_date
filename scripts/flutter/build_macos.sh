#!/usr/bin/env bash
set -euo pipefail
: "${BUILD_NAME:?BUILD_NAME is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
APP_NAME="${APP_NAME:-Runner}"
TASK_DIR="$(mktemp -d)"
KEYCHAIN="$TASK_DIR/everup.keychain-db"
cleanup() {
  if [[ -f "$KEYCHAIN" ]]; then security delete-keychain "$KEYCHAIN"; fi
  rm -rf "$TASK_DIR"
}
trap cleanup EXIT
if [[ -n "${EVERUP_MACOS_SECRETS:-}" ]]; then
  eval "$(python3 -c '
import json, os, shlex
try:
    d = json.loads(os.environ["EVERUP_MACOS_SECRETS"])
    for k, v in [
        ("MACOS_CERTIFICATE_BASE64", d.get("certificate_base64")),
        ("MACOS_CERTIFICATE_PASSWORD", d.get("certificate_password")),
        ("MACOS_SIGNING_IDENTITY", d.get("signing_identity")),
        ("APPLE_ID", d.get("apple_id")),
        ("APPLE_APP_PASSWORD", d.get("apple_app_password")),
        ("APPLE_TEAM_ID", d.get("apple_team_id")),
    ]:
        if v:
            print(f"export {k}={shlex.quote(str(v))}")
except Exception:
    pass
')"
fi
if [[ "${REQUIRE_PLATFORM_SIGNING:-false}" == true && -z "${MACOS_CERTIFICATE_BASE64:-}" ]]; then
  echo 'macOS Developer ID certificate is required' >&2; exit 1
fi
flutter pub get
flutter build macos --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  APPS=()
  while IFS= read -r -d '' app; do APPS+=("$app"); done < <(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print0)
  [[ ${#APPS[@]} == 1 ]] || { echo 'Expected exactly one .app bundle' >&2; exit 1; }
  APP_PATH="${APPS[0]}"
  APP_NAME="$(basename "$APP_PATH" .app)"
fi
if [[ -n "${MACOS_CERTIFICATE_BASE64:-}" ]]; then
  : "${MACOS_CERTIFICATE_PASSWORD:?Certificate password is required}"
  : "${MACOS_SIGNING_IDENTITY:?Developer ID identity is required}"
  : "${APPLE_ID:?Apple ID is required}"
  : "${APPLE_APP_PASSWORD:?Notarization password is required}"
  : "${APPLE_TEAM_ID:?Team ID is required}"
  python3 -c 'import base64,os,sys; open(sys.argv[1],"wb").write(base64.b64decode(os.environ["MACOS_CERTIFICATE_BASE64"],validate=True))' "$TASK_DIR/certificate.p12"
  KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$TASK_DIR/certificate.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # Sign nested frameworks and executables before the enclosing app.
  while IFS= read -r -d '' binary; do
    codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" --sign "$MACOS_SIGNING_IDENTITY" "$binary"
  done < <(find "$APP_PATH/Contents" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -depth -print0)
  codesign --force --timestamp --options runtime --entitlements macos/Runner/Release.entitlements --keychain "$KEYCHAIN" --sign "$MACOS_SIGNING_IDENTITY" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi
OUTPUT_DMG="build/macos/Build/Products/Release/${APP_NAME}-v${BUILD_NAME}.dmg"
if command -v create-dmg >/dev/null; then
  create-dmg --volname "$APP_NAME Installer" --window-size 600 400 --icon-size 100 \
    --icon "$APP_NAME.app" 175 120 --hide-extension "$APP_NAME.app" --app-drop-link 425 120 \
    "$OUTPUT_DMG" "$APP_PATH"
else
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$OUTPUT_DMG"
fi
[[ -s "$OUTPUT_DMG" ]] || { echo 'DMG missing' >&2; exit 1; }
if [[ -n "${MACOS_CERTIFICATE_BASE64:-}" ]]; then
  codesign --timestamp --keychain "$KEYCHAIN" --sign "$MACOS_SIGNING_IDENTITY" "$OUTPUT_DMG"
  xcrun notarytool submit "$OUTPUT_DMG" --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait --output-format json > "$TASK_DIR/notarization.json"
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); sys.exit(0 if data.get("status")=="Accepted" else "Notarization rejected")' "$TASK_DIR/notarization.json"
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"
fi
echo "Built DMG: $OUTPUT_DMG"
