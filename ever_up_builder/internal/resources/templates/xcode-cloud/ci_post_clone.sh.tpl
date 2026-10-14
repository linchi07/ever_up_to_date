#!/usr/bin/env bash
set -euo pipefail
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
cd "$CI_PRIMARY_REPOSITORY_PATH"
if ! command -v flutter >/dev/null; then brew install --cask flutter; fi
if ! command -v pod >/dev/null; then brew install cocoapods; fi
flutter precache --ios
flutter pub get
cd ios
pod install
