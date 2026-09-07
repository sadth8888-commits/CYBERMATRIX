#!/usr/bin/env bash
set -euo pipefail

flutter create --platforms=android --org ir.cybermatrix --project-name cybermatrix_tunnel .
flutter pub get
flutter analyze
flutter build apk --release

echo "APK: build/app/outputs/flutter-apk/app-release.apk"
