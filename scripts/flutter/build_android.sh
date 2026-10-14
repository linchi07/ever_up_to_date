#!/usr/bin/env bash
set -euo pipefail

# Build script for Android release APK
echo "==> Building Flutter Android APK (Release)..."
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_NAME="${BUILD_NAME:-1.0.0}"

flutter build apk --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

OUTPUT_APK="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$OUTPUT_APK" ]; then
  echo "Error: APK not found at $OUTPUT_APK" >&2
  exit 1
fi

echo "==> Successfully built Android APK: $OUTPUT_APK"
