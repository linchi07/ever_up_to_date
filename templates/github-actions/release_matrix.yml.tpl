name: EverUp Release Pipeline

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      version:
        description: 'Semantic version (required when running on a branch)'
        required: true
      build_number:
        description: 'Positive build number; defaults to workflow run number'
        required: false
      channel:
        description: 'Release channel'
        type: choice
        options: [stable, beta]
        default: beta

permissions:
  contents: read
concurrency:
  group: everup-publish
  cancel-in-progress: false

env:
  APP_ID: {{ yaml .AppID }}
  S3_BUCKET: {{ yaml .S3Bucket }}
  S3_ENDPOINT_URL: {{ yaml .S3Endpoint }}
  S3_PREFIX: {{ yaml .S3Prefix }}
  MANIFEST_URL: {{ yaml .ManifestURL }}
  ROLLOUT_PERCENTAGE: '{{ .RolloutPercentage }}'
  ENABLE_ANDROID: '{{ .EnableAndroid }}'
  ENABLE_WINDOWS: '{{ .EnableWindows }}'
  ENABLE_MACOS: '{{ .EnableMacOS }}'
  ENABLE_IOS: '{{ .EnableIOS }}'
  IOS_STORE_URL: {{ yaml .IOSStoreURL }}
  IOS_PACKAGE_TYPE: {{ yaml .IOSPackageType }}
  REQUIRE_PLATFORM_SIGNING: '{{ .RequirePlatformSigning }}'

jobs:
  metadata:
    runs-on: ubuntu-latest
    outputs:
      version: ${{"{{"}} steps.release.outputs.version {{"}}"}}
      build_number: ${{"{{"}} steps.release.outputs.build_number {{"}}"}}
      channel: ${{"{{"}} steps.release.outputs.channel {{"}}"}}
    steps:
      - uses: actions/checkout@v4
      - id: release
        env:
          INPUT_VERSION: ${{"{{"}} inputs.version {{"}}"}}
          INPUT_BUILD_NUMBER: ${{"{{"}} inputs.build_number {{"}}"}}
          INPUT_CHANNEL: ${{"{{"}} inputs.channel {{"}}"}}
          RELEASE_TAG: ${{"{{"}} github.ref_name {{"}}"}}
        run: bash scripts/common/release_metadata.sh
{{ if .EnableAndroid }}
  build-android:
    needs: metadata
    runs-on: ubuntu-latest
    env:
      BUILD_NAME: ${{"{{"}} needs.metadata.outputs.version {{"}}"}}
      BUILD_NUMBER: ${{"{{"}} needs.metadata.outputs.build_number {{"}}"}}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Build and sign APK
        env:
          EVERUP_ANDROID_SECRETS: ${{"{{"}} secrets.EVERUP_ANDROID_SECRETS {{"}}"}}
          ANDROID_KEYSTORE_BASE64: ${{"{{"}} secrets.ANDROID_KEYSTORE_BASE64 {{"}}"}}
          ANDROID_KEYSTORE_PASSWORD: ${{"{{"}} secrets.ANDROID_KEYSTORE_PASSWORD {{"}}"}}
          ANDROID_KEY_ALIAS: ${{"{{"}} secrets.ANDROID_KEY_ALIAS {{"}}"}}
          ANDROID_KEY_PASSWORD: ${{"{{"}} secrets.ANDROID_KEY_PASSWORD {{"}}"}}
        run: bash scripts/flutter/build_android.sh
      - uses: actions/upload-artifact@v4
        with:
          name: android-apk
          path: build/app/outputs/flutter-apk/app-release.apk
          if-no-files-found: error
{{ end }}
{{ if .EnableWindows }}
  build-windows:
    needs: metadata
    runs-on: windows-latest
    env:
      BUILD_NAME: ${{"{{"}} needs.metadata.outputs.version {{"}}"}}
      BUILD_NUMBER: ${{"{{"}} needs.metadata.outputs.build_number {{"}}"}}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Install Inno Setup
        run: choco install innosetup --no-progress -y
      - name: Build and sign installer
        env:
          EVERUP_WINDOWS_SECRETS: ${{"{{"}} secrets.EVERUP_WINDOWS_SECRETS {{"}}"}}
          WINDOWS_CERTIFICATE_BASE64: ${{"{{"}} secrets.WINDOWS_CERTIFICATE_BASE64 {{"}}"}}
          WINDOWS_CERTIFICATE_PASSWORD: ${{"{{"}} secrets.WINDOWS_CERTIFICATE_PASSWORD {{"}}"}}
        run: ./scripts/flutter/build_windows.ps1
      - uses: actions/upload-artifact@v4
        with:
          name: windows-installer
          path: build/windows/installer/*.exe
          if-no-files-found: error
{{ end }}
{{ if .EnableMacOS }}
  build-macos:
    needs: metadata
    runs-on: macos-latest
    env:
      BUILD_NAME: ${{"{{"}} needs.metadata.outputs.version {{"}}"}}
      BUILD_NUMBER: ${{"{{"}} needs.metadata.outputs.build_number {{"}}"}}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: brew install create-dmg
      - name: Build, sign and notarize DMG
        env:
          EVERUP_MACOS_SECRETS: ${{"{{"}} secrets.EVERUP_MACOS_SECRETS {{"}}"}}
          MACOS_CERTIFICATE_BASE64: ${{"{{"}} secrets.MACOS_CERTIFICATE_BASE64 {{"}}"}}
          MACOS_CERTIFICATE_PASSWORD: ${{"{{"}} secrets.MACOS_CERTIFICATE_PASSWORD {{"}}"}}
          MACOS_SIGNING_IDENTITY: ${{"{{"}} secrets.MACOS_SIGNING_IDENTITY {{"}}"}}
          APPLE_ID: ${{"{{"}} secrets.APPLE_ID {{"}}"}}
          APPLE_APP_PASSWORD: ${{"{{"}} secrets.APPLE_APP_PASSWORD {{"}}"}}
          APPLE_TEAM_ID: ${{"{{"}} secrets.APPLE_TEAM_ID {{"}}"}}
        run: bash scripts/flutter/build_macos.sh
      - uses: actions/upload-artifact@v4
        with:
          name: macos-dmg
          path: build/macos/Build/Products/Release/*.dmg
          if-no-files-found: error
{{ end }}
  publish-appcast:
    needs: [metadata{{ if .EnableAndroid }}, build-android{{ end }}{{ if .EnableWindows }}, build-windows{{ end }}{{ if .EnableMacOS }}, build-macos{{ end }}]
    runs-on: ubuntu-latest
    env:
      BUILD_NAME: ${{"{{"}} needs.metadata.outputs.version {{"}}"}}
      BUILD_NUMBER: ${{"{{"}} needs.metadata.outputs.build_number {{"}}"}}
      RELEASE_CHANNEL: ${{"{{"}} needs.metadata.outputs.channel {{"}}"}}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23.x'
      - name: Resolve S3 credentials
        env:
          EVERUP_COMMON_SECRETS: ${{"{{"}} secrets.EVERUP_COMMON_SECRETS {{"}}"}}
          S3_ACCESS_KEY_ID: ${{"{{"}} secrets.S3_ACCESS_KEY_ID {{"}}"}}
          S3_SECRET_ACCESS_KEY: ${{"{{"}} secrets.S3_SECRET_ACCESS_KEY {{"}}"}}
        run: |
          python3 - << 'PY'
          import json, os
          key_id = os.environ.get('S3_ACCESS_KEY_ID', '')
          secret_key = os.environ.get('S3_SECRET_ACCESS_KEY', '')
          raw = os.environ.get('EVERUP_COMMON_SECRETS', '').strip()
          if raw:
              try:
                  data = json.loads(raw)
                  key_id = data.get('s3_access_key_id') or key_id
                  secret_key = data.get('s3_secret_access_key') or secret_key
              except Exception:
                  pass
          with open(os.environ['GITHUB_ENV'], 'a') as f:
              f.write(f"AWS_ACCESS_KEY_ID={key_id}\n")
              f.write(f"AWS_SECRET_ACCESS_KEY={secret_key}\n")
          PY
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{"{{"}} env.AWS_ACCESS_KEY_ID {{"}}"}}
          aws-secret-access-key: ${{"{{"}} env.AWS_SECRET_ACCESS_KEY {{"}}"}}
          aws-region: {{ yaml .S3Region }}
{{ if or .EnableAndroid .EnableWindows .EnableMacOS }}
      - uses: actions/download-artifact@v4
        with:
          path: artifacts
{{ end }}
      - name: Sign, upload artifacts and publish manifest
        env:
          EVERUP_COMMON_SECRETS: ${{"{{"}} secrets.EVERUP_COMMON_SECRETS {{"}}"}}
          PRIVATE_KEY: ${{"{{"}} secrets.EVERUP_SIGNING_PRIVATE_KEY {{"}}"}}
        run: bash scripts/common/publish_release.sh artifacts
