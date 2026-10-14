#!/usr/bin/env bash
# Xcode Cloud CI Post-Clone Hook for Flutter
set -e

# Fail this script if any subcommand fails.
set -o pipefail

echo "==> Xcode Cloud: Installing Homebrew and dependencies..."
export HOMEBREW_NO_INSTALL_CLEANUP=TRUE
brew install --cask flutter
brew install cocoapods

echo "==> Flutter Doctor check..."
flutter doctor -v

echo "==> Pre-caching Flutter iOS artifacts..."
flutter precache --ios

echo "==> Getting Flutter dependencies..."
flutter pub get

# Navigate to iOS directory and run pod install
cd ios
pod install

echo "==> Xcode Cloud Post-Clone setup completed successfully."
exit 0
