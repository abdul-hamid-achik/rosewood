#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${PROJECT:-$ROOT_DIR/Rosewood.xcodeproj}"
SCHEME="${SCHEME:-Rosewood}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
APP_NAME="${APP_NAME:-Rosewood}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_DIR/$APP_NAME.xcarchive}"
SIGNED_APP_PATH="${SIGNED_APP_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$OUTPUT_DIR/$APP_NAME.zip}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 1
  fi
}

require_env APPLE_TEAM_ID
require_env DEVELOPER_ID_APPLICATION

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH" "$SIGNED_APP_PATH" "$ZIP_PATH"

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  printf 'Expected archived app at %s\n' "$APP_PATH" >&2
  exit 1
fi

ditto "$APP_PATH" "$SIGNED_APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$SIGNED_APP_PATH" "$ZIP_PATH"

printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'Signed app: %s\n' "$SIGNED_APP_PATH"
printf 'Zip: %s\n' "$ZIP_PATH"
