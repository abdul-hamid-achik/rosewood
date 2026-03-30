#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-Rosewood}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
SIGNED_APP_PATH="${SIGNED_APP_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$OUTPUT_DIR/$APP_NAME.zip}"
NOTARIZED_ZIP_PATH="${NOTARIZED_ZIP_PATH:-$OUTPUT_DIR/$APP_NAME-notarized.zip}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'Required file not found: %s\n' "$path" >&2
    exit 1
  fi
}

require_env NOTARY_KEYCHAIN_PROFILE
require_file "$SIGNED_APP_PATH"
require_file "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait

xcrun stapler staple "$SIGNED_APP_PATH"
xcrun stapler validate "$SIGNED_APP_PATH"

rm -f "$NOTARIZED_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP_PATH" "$NOTARIZED_ZIP_PATH"

printf 'Stapled app: %s\n' "$SIGNED_APP_PATH"
printf 'Notarized zip: %s\n' "$NOTARIZED_ZIP_PATH"
