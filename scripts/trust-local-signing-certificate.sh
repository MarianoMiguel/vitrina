#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT="$ROOT/.local-codesign/cert.pem"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

"$ROOT/scripts/ensure-local-signing-identity.sh" >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$LOGIN_KEYCHAIN" \
  "$CERT" >/dev/null

echo "Trusted Dynamic Share Target local signing certificate for code signing"
