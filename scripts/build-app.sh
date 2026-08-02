#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vitrina"
CONFIG="${CONFIGURATION:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Vitrina Local}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/vitrina"
APP="$OUTPUT_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/vitrina"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  KEYCHAIN="$("$ROOT/scripts/ensure-local-signing-identity.sh")"
  CURRENT_KEYCHAINS="$(security list-keychains -d user | sed 's/^[[:space:]]*//;s/"//g')"
  if ! printf '%s\n' "$CURRENT_KEYCHAINS" | grep -Fxq "$KEYCHAIN"; then
    # codesign only resolves identities from the active search list on recent macOS.
    security list-keychains -d user -s "$KEYCHAIN" $CURRENT_KEYCHAINS
  fi

  SIGN_IDENTITY_HASH="$(
    security find-identity -v -p codesigning "$KEYCHAIN" |
      awk -v name="$SIGN_IDENTITY" 'index($0, name) { print $2; exit }'
  )"

  if [[ -n "$SIGN_IDENTITY_HASH" ]]; then
    codesign --force --sign "$SIGN_IDENTITY_HASH" "$APP" >/dev/null
  else
    echo "warning: local signing identity not found; falling back to ad-hoc signing" >&2
    codesign --force --sign - "$APP" >/dev/null
  fi
fi

echo "$APP"
