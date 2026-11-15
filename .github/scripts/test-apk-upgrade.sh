#!/usr/bin/env bash
set -euo pipefail

BETA_APK="$GITHUB_WORKSPACE/artifacts/beta/app-release.apk"
PRODUCTION_APK="$GITHUB_WORKSPACE/artifacts/production/app-release.apk"
RESULTS="$GITHUB_WORKSPACE/test-results"
mkdir -p "$RESULTS"

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
AAPT="$(find "$SDK_ROOT/build-tools" -type f -name aapt | sort -V | tail -n 1)"
APKSIGNER="$(find "$SDK_ROOT/build-tools" -type f -name apksigner | sort -V | tail -n 1)"
if [[ -z "$AAPT" || -z "$APKSIGNER" ]]; then
  echo "::error::Android aapt or apksigner was not found."
  exit 1
fi

{
  echo "=== Emulator ==="
  adb shell getprop ro.build.version.release
  adb shell getprop ro.build.version.sdk
  echo "=== APK metadata ==="
  "$AAPT" dump badging "$BETA_APK" | sed -n '1p'
  "$AAPT" dump badging "$PRODUCTION_APK" | sed -n '1p'
  echo "=== Signing certificates ==="
  "$APKSIGNER" verify --print-certs "$BETA_APK"
  "$APKSIGNER" verify --print-certs "$PRODUCTION_APK"
} | tee "$RESULTS/preflight.txt"

BETA_PACKAGE="$("$AAPT" dump badging "$BETA_APK" | sed -n "1s/.*name='\\([^']*\\)'.*/\\1/p")"
PROD_PACKAGE="$("$AAPT" dump badging "$PRODUCTION_APK" | sed -n "1s/.*name='\\([^']*\\)'.*/\\1/p")"
BETA_CODE="$("$AAPT" dump badging "$BETA_APK" | sed -n "1s/.*versionCode='\\([^']*\\)'.*/\\1/p")"
PROD_CODE="$("$AAPT" dump badging "$PRODUCTION_APK" | sed -n "1s/.*versionCode='\\([^']*\\)'.*/\\1/p")"
BETA_CERT="$("$APKSIGNER" verify --print-certs "$BETA_APK" | sed -n 's/.*certificate SHA-256 digest: //p' | sed -n '1p' | tr -d ':' | tr '[:lower:]' '[:upper:]')"
PROD_CERT="$("$APKSIGNER" verify --print-certs "$PRODUCTION_APK" | sed -n 's/.*certificate SHA-256 digest: //p' | sed -n '1p' | tr -d ':' | tr '[:lower:]' '[:upper:]')"

if [[ "$BETA_PACKAGE" != "$PROD_PACKAGE" ]]; then
  echo "::error::Package ID mismatch: beta=$BETA_PACKAGE production=$PROD_PACKAGE"
  exit 1
fi
if [[ "$BETA_CERT" != "$PROD_CERT" ]]; then
  echo "::error::Signing certificate mismatch between beta and production APKs."
  exit 1
fi
if ! [[ "$BETA_CODE" =~ ^[0-9]+$ && "$PROD_CODE" =~ ^[0-9]+$ ]] || (( PROD_CODE < BETA_CODE )); then
  echo "::error::Production versionCode ($PROD_CODE) is lower than beta versionCode ($BETA_CODE)."
  exit 1
fi

echo "Preflight passed: package ID, signer and versionCode are upgrade-compatible."
echo "=== Install beta APK ==="
if ! adb install "$BETA_APK" > "$RESULTS/beta-install.txt" 2>&1; then
  cat "$RESULTS/beta-install.txt"
  adb logcat -d -b all > "$RESULTS/logcat-beta-install-failure.txt" || true
  exit 1
fi
cat "$RESULTS/beta-install.txt"
adb shell dumpsys package "$BETA_PACKAGE" > "$RESULTS/installed-beta-package.txt"

echo "=== Upgrade to production APK without uninstalling ==="
if adb install -r "$PRODUCTION_APK" > "$RESULTS/production-upgrade.txt" 2>&1; then
  cat "$RESULTS/production-upgrade.txt"
  adb shell dumpsys package "$PROD_PACKAGE" > "$RESULTS/installed-production-package.txt"
  adb shell monkey -p "$PROD_PACKAGE" 1 > "$RESULTS/launch-app.txt" 2>&1 || true
  echo "UPGRADE_TEST_RESULT=PASS" | tee "$RESULTS/result.txt"
  echo "In-place beta-to-production upgrade succeeded."
else
  INSTALL_EXIT=$?
  cat "$RESULTS/production-upgrade.txt"
  adb shell dumpsys package "$BETA_PACKAGE" > "$RESULTS/installed-package-after-failure.txt" || true
  adb logcat -d -b all > "$RESULTS/logcat-upgrade-failure.txt" || true
  echo "UPGRADE_TEST_RESULT=FAIL (adb install exit $INSTALL_EXIT)" | tee "$RESULTS/result.txt"
  exit "$INSTALL_EXIT"
fi
