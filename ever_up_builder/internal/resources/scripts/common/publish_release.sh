#!/usr/bin/env bash
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET is required}"
: "${MANIFEST_URL:?MANIFEST_URL is required}"
: "${BUILD_NAME:?BUILD_NAME is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${RELEASE_CHANNEL:?RELEASE_CHANNEL is required}"
ARTIFACT_DIR="${1:-artifacts}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$(mktemp -d)"
trap 'rm -rf "$TASK_DIR"' EXIT
ENDPOINT_ARGS=()
if [[ -n "${S3_ENDPOINT_URL:-}" ]]; then ENDPOINT_ARGS=(--endpoint-url "$S3_ENDPOINT_URL"); fi
PREFIX="${S3_PREFIX:-}"
PREFIX="${PREFIX%/}"
if [[ -n "$PREFIX" ]]; then PREFIX="$PREFIX/"; fi
MANIFEST_KEY="${PREFIX}appcast.json"
PUBLIC_BASE="${MANIFEST_URL%/*}"
ETAG=""
if aws s3api head-object --bucket "$S3_BUCKET" --key "$MANIFEST_KEY" "${ENDPOINT_ARGS[@]}" > "$TASK_DIR/head.json" 2> "$TASK_DIR/head.err"; then
  ETAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ETag"])' "$TASK_DIR/head.json")"
  aws s3 cp "s3://$S3_BUCKET/$MANIFEST_KEY" "$TASK_DIR/appcast.json" "${ENDPOINT_ARGS[@]}"
else
  if ! grep -Eq '404|Not Found|NoSuchKey' "$TASK_DIR/head.err"; then cat "$TASK_DIR/head.err" >&2; exit 1; fi
  # Start from an empty manifest. A checked-in sample must never become a real release.
fi

hash_file() {
  python3 -c 'import hashlib,sys; digest=hashlib.sha256(); f=open(sys.argv[1],"rb"); [digest.update(block) for block in iter(lambda:f.read(1048576),b"")]; print(digest.hexdigest())' "$1"
}
upload_immutable() {
  local file="$1" key="$2" content_type="$3" digest
  digest="$(hash_file "$file")"
  if aws s3api head-object --bucket "$S3_BUCKET" --key "$key" "${ENDPOINT_ARGS[@]}" > "$TASK_DIR/object-head.json" 2> "$TASK_DIR/object-head.err"; then
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); sys.exit(0 if data.get("Metadata",{}).get("sha256")==sys.argv[2] else "Immutable object checksum mismatch")' "$TASK_DIR/object-head.json" "$digest"
    return
  elif ! grep -Eq '404|Not Found|NoSuchKey' "$TASK_DIR/object-head.err"; then cat "$TASK_DIR/object-head.err" >&2; exit 1; fi
  aws s3api put-object --bucket "$S3_BUCKET" --key "$key" --body "$file" \
    --if-none-match '*' --metadata "sha256=$digest" --content-type "$content_type" \
    --cache-control 'public,max-age=31536000,immutable' "${ENDPOINT_ARGS[@]}"
}

publish_binary() {
  local platform="$1" kind="$2" folder="$3" extension="$4"
  local files=()
  while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$ARTIFACT_DIR/$folder" -type f -name "*.$extension" -print0)
  if [[ ${#files[@]} != 1 ]]; then echo "Expected one $platform artifact, got ${#files[@]}" >&2; exit 1; fi
  local digest
  digest="$(hash_file "${files[0]}")"
  local relative="releases/$RELEASE_CHANNEL/$BUILD_NAME/$BUILD_NUMBER/$platform-$digest.$extension"
  go run "$SCRIPT_DIR/update_appcast.go" --manifest="$TASK_DIR/appcast.json" \
    --app-id="${APP_ID:?APP_ID is required}" --channel="$RELEASE_CHANNEL" \
    --version="$BUILD_NAME" --build-number="$BUILD_NUMBER" --rollout-percentage="${ROLLOUT_PERCENTAGE:-100}" --platform="$platform" \
    --type="$kind" --file="${files[0]}" --url="$PUBLIC_BASE/$relative"
  upload_immutable "${files[0]}" "$PREFIX$relative" application/octet-stream
}

if [[ "${ENABLE_ANDROID:-false}" == true ]]; then publish_binary android direct_apk android-apk apk; fi
if [[ "${ENABLE_WINDOWS:-false}" == true ]]; then publish_binary windows inno_setup windows-installer exe; fi
if [[ "${ENABLE_MACOS:-false}" == true ]]; then publish_binary macos dmg macos-dmg dmg; fi
if [[ "${ENABLE_IOS:-false}" == true ]]; then
  go run "$SCRIPT_DIR/update_appcast.go" --manifest="$TASK_DIR/appcast.json" \
    --app-id="${APP_ID:?APP_ID is required}" --channel="$RELEASE_CHANNEL" \
    --version="$BUILD_NAME" --build-number="$BUILD_NUMBER" --rollout-percentage="${ROLLOUT_PERCENTAGE:-100}" --platform=ios \
    --type="${IOS_PACKAGE_TYPE:-testflight}" --url="${IOS_STORE_URL:?IOS_STORE_URL is required}"
fi
[[ -f "$TASK_DIR/appcast.json" ]] || { echo 'No enabled release targets' >&2; exit 1; }
SNAPSHOT_DIGEST="$(hash_file "$TASK_DIR/appcast.json")"
upload_immutable "$TASK_DIR/appcast.json" "${PREFIX}releases/$RELEASE_CHANNEL/$BUILD_NAME/$BUILD_NUMBER/appcast-$SNAPSHOT_DIGEST.json" application/json
# Publish discovery metadata last. Concurrent writers must not overwrite each other.
CONDITION_ARGS=(--if-none-match '*')
if [[ -n "$ETAG" ]]; then CONDITION_ARGS=(--if-match "$ETAG"); fi
aws s3api put-object --bucket "$S3_BUCKET" --key "$MANIFEST_KEY" \
  --body "$TASK_DIR/appcast.json" --content-type application/json --cache-control 'no-cache,max-age=0' \
  "${CONDITION_ARGS[@]}" "${ENDPOINT_ARGS[@]}"
echo "Published $RELEASE_CHANNEL $BUILD_NAME+$BUILD_NUMBER"
