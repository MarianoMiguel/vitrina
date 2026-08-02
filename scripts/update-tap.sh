#!/usr/bin/env bash
# Writes Casks/vitrina.rb in MarianoMiguel/homebrew-tap for a released
# version. Called by release.sh; safe to run standalone:
#   scripts/update-tap.sh 0.1.0 <sha256-of-release-zip>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_REPO="MarianoMiguel/homebrew-tap"
VERSION="${1:?usage: update-tap.sh <version> <sha256>}"
SHA256="${2:?usage: update-tap.sh <version> <sha256>}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

gh repo clone "$TAP_REPO" "$WORKDIR/tap" -- --depth 1
mkdir -p "$WORKDIR/tap/Casks"
sed -e "s/@@VERSION@@/$VERSION/" -e "s/@@SHA256@@/$SHA256/" \
  "$ROOT/packaging/vitrina.rb.template" > "$WORKDIR/tap/Casks/vitrina.rb"

cd "$WORKDIR/tap"
git add Casks/vitrina.rb
if git diff --cached --quiet; then
  echo "tap already up to date"
  exit 0
fi
git commit -m "vitrina $VERSION"
git push
echo "tap updated: brew install marianomiguel/tap/vitrina"
