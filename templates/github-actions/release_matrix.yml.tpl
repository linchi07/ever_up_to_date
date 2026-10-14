name: EverUp Release Pipeline

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      channel:
        description: 'Release Channel (stable, beta)'
        required: true
        default: 'beta'

jobs:
{{- if .EnableAndroid }}
  build-android:
    name: Build Android APK
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Build APK
        run: |
          chmod +x scripts/flutter/build_android.sh
          ./scripts/flutter/build_android.sh

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-apk
          path: build/app/outputs/flutter-apk/app-release.apk
{{- end }}

{{- if .EnableWindows }}
  build-windows:
    name: Build Windows Installer
    runs-on: windows-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Setup Inno Setup
        uses: stack-of-tasks/setup-inno-setup@v1

      - name: Build and Package Windows
        run: |
          powershell -ExecutionPolicy Bypass -File scripts/flutter/build_windows.ps1

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: windows-installer
          path: build/windows/installer/*.exe
{{- end }}

{{- if .EnableMacOS }}
  build-macos:
    name: Build macOS DMG
    runs-on: macos-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Build and Package DMG
        run: |
          chmod +x scripts/flutter/build_macos.sh
          ./scripts/flutter/build_macos.sh

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: macos-dmg
          path: build/macos/Build/Products/Release/*.dmg
{{- end }}

  publish-appcast:
    name: Publish Artifacts & Update Appcast
    needs: [
      {{- if .EnableAndroid }}build-android,{{- end }}
      {{- if .EnableWindows }}build-windows,{{- end }}
      {{- if .EnableMacOS }}build-macos,{{- end }}
    ]
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.23'

      - name: Setup AWS CLI
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{"{{"}} secrets.S3_ACCESS_KEY_ID {{"}}"}}
          aws-secret-access-key: ${{"{{"}} secrets.S3_SECRET_ACCESS_KEY {{"}}"}}
          aws-region: 'auto'

      - name: Download all build artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Update Appcast Manifest & Sync S3
        env:
          S3_BUCKET: ${{"{{"}} secrets.S3_BUCKET {{"}}"}}
          S3_ENDPOINT_URL: ${{"{{"}} secrets.S3_ENDPOINT_URL {{"}}"}}
          PRIVATE_KEY: ${{"{{"}} secrets.EVERUP_SIGNING_PRIVATE_KEY {{"}}"}}
        run: |
          # Fetch existing appcast.json from S3 if available
          aws s3 cp s3://$S3_BUCKET/appcast.json appcast.json $ENDPOINT_ARG || true

          # Iterate through artifacts and invoke update_appcast.go
          go run scripts/common/update_appcast.go \
            --manifest=appcast.json \
            --channel=${{"{{"}} inputs.channel || 'beta' {{"}}"}} \
            --version=${{"{{"}} github.ref_name {{"}}"}} \
            --private-key="$PRIVATE_KEY"

          # Upload updated appcast.json back to S3
          chmod +x scripts/common/s3_upload.sh
          ./scripts/common/s3_upload.sh appcast.json appcast.json
