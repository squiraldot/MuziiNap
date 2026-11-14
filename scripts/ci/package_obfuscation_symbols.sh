#!/usr/bin/env bash
set -euo pipefail
SYMBOLS_ROOT="${1:?Usage: package_obfuscation_symbols.sh <symbols-root> <output-dir>}"
OUTPUT_DIR="${2:?Usage: package_obfuscation_symbols.sh <symbols-root> <output-dir>}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
: "${APP_VERSION:?APP_VERSION is required}"
: "${SYMBOLS_ENCRYPTION_KEY:?Set the repository Actions secret SYMBOLS_ENCRYPTION_KEY}"
PUBSPEC_VERSION="$(awk -F': ' '$1 == "version" {print $2; exit}' pubspec.yaml)"
test -n "$PUBSPEC_VERSION"
test "$APP_VERSION" = "$PUBSPEC_VERSION" || { echo "::error::APP_VERSION does not match pubspec.yaml."; exit 1; }
SYMBOL_COUNT="$(find "$SYMBOLS_ROOT" -type f -name '*.symbols' -size +0c | wc -l | tr -d ' ')"
if [ "$SYMBOL_COUNT" -lt 1 ]; then
  echo "::error::No non-empty Flutter Dart AOT symbol files were generated."
  exit 1
fi
BUILD_ID="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/muziinap-symbols-${GITHUB_SHA}-${APP_VERSION}-${BUILD_ID}.tar.gz"
ENCRYPTED="$ARCHIVE.gpg"
VERIFY_ARCHIVE="$OUTPUT_DIR/.verify-${BUILD_ID}.tar.gz"
cleanup() { rm -f "$ARCHIVE" "$VERIFY_ARCHIVE"; rm -rf "$SYMBOLS_ROOT"; }
trap cleanup EXIT
cat > "$SYMBOLS_ROOT/manifest.txt" <<EOF
Repository: squiraldot/MuziiNap
Commit: ${GITHUB_SHA}
Version: ${APP_VERSION}
Build ID: ${BUILD_ID}
Run ID: ${GITHUB_RUN_ID}
Run attempt: ${GITHUB_RUN_ATTEMPT}
Ref: ${GITHUB_REF:-unknown}
Symbol files: ${SYMBOL_COUNT}
EOF
tar -czf "$ARCHIVE" -C "$SYMBOLS_ROOT" .
printf '%s\n' "$SYMBOLS_ENCRYPTION_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$ENCRYPTED" "$ARCHIVE"
chmod 600 "$ENCRYPTED"
test -s "$ENCRYPTED"
printf '%s\n' "$SYMBOLS_ENCRYPTION_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --decrypt --output "$VERIFY_ARCHIVE" "$ENCRYPTED"
tar -tzf "$VERIFY_ARCHIVE" >/dev/null
echo "Encrypted and integrity-checked $SYMBOL_COUNT Dart AOT symbol file(s)."
echo "Encrypted symbol archive: $ENCRYPTED"
