#!/usr/bin/env bash
set -euo pipefail
: "${BUILD_NAME:?BUILD_NAME is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
if [[ -z "${EVERUP_ANDROID_SECRETS:-}" && -f ".everup/secrets.json" ]]; then
  EVERUP_ANDROID_SECRETS="$(python3 -c 'import json; print(json.dumps(json.load(open(".everup/secrets.json")).get("android", {})))' 2>/dev/null || true)"
fi
if [[ -n "${EVERUP_ANDROID_SECRETS:-}" ]]; then
  eval "$(python3 -c '
import json, os, shlex
try:
    d = json.loads(os.environ["EVERUP_ANDROID_SECRETS"])
    for k, v in [
        ("ANDROID_KEYSTORE_BASE64", d.get("keystore_base64")),
        ("ANDROID_KEYSTORE_PASSWORD", d.get("keystore_password")),
        ("ANDROID_KEY_ALIAS", d.get("key_alias")),
        ("ANDROID_KEY_PASSWORD", d.get("key_password")),
    ]:
        if v:
            print(f"export {k}={shlex.quote(str(v))}")
except Exception:
    pass
')"
fi
if [[ "${REQUIRE_PLATFORM_SIGNING:-false}" == true && -z "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo 'Android release keystore is required' >&2; exit 1
fi
flutter pub get
flutter build apk --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
OUTPUT_APK='build/app/outputs/flutter-apk/app-release.apk'
[[ -s "$OUTPUT_APK" ]] || { echo 'Release APK missing' >&2; exit 1; }
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  : "${ANDROID_KEYSTORE_PASSWORD:?Keystore password is required}"
  : "${ANDROID_KEY_ALIAS:?Key alias is required}"
  : "${ANDROID_KEY_PASSWORD:?Key password is required}"
  TASK_DIR="$(mktemp -d)"
  trap 'rm -rf "$TASK_DIR"' EXIT
  python3 -c 'import base64,os,sys; open(sys.argv[1],"wb").write(base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"],validate=True))' "$TASK_DIR/release.jks"
  chmod 600 "$TASK_DIR/release.jks"
  SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?Android SDK is required}}"
  APKSIGNER="$(find "$SDK_ROOT/build-tools" -name apksigner -type f | sort -V | tail -n 1)"
  [[ -n "$APKSIGNER" ]] || { echo 'apksigner not found' >&2; exit 1; }
  "$APKSIGNER" sign --ks "$TASK_DIR/release.jks" --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --ks-pass env:ANDROID_KEYSTORE_PASSWORD --key-pass env:ANDROID_KEY_PASSWORD \
    --out "$TASK_DIR/signed.apk" "$OUTPUT_APK"
  "$APKSIGNER" verify "$TASK_DIR/signed.apk"
  mv "$TASK_DIR/signed.apk" "$OUTPUT_APK"
fi
echo "Built APK: $OUTPUT_APK"
