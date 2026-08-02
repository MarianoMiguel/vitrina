#!/usr/bin/env bash
# Cuts a Vitrina release: stamps the version, builds a Release bundle, signs
# it (Developer ID + notarization when configured, local identity otherwise),
# zips it, generates the appcast, tags, publishes the GitHub release, and
# updates the Homebrew tap.
#
# Usage:
#   scripts/release.sh 0.1.0                 # full release
#   scripts/release.sh 0.1.0 --dry-run       # build + zip + appcast only
#
# Optional environment for distribution-grade signing:
#   RELEASE_SIGN_IDENTITY   e.g. "Developer ID Application: Mariano Miguel (TEAMID)"
#   NOTARY_PROFILE          notarytool keychain profile (xcrun notarytool store-credentials)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="MarianoMiguel/vitrina"
VERSION="${1:-}"
DRY_RUN="${2:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <semver> [--dry-run]" >&2
  exit 1
fi

if [[ "$DRY_RUN" != "--dry-run" ]]; then
  if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "error: working tree is not clean; commit or stash first" >&2
    exit 1
  fi
  if [[ "$(git -C "$ROOT" branch --show-current)" != "main" ]]; then
    echo "error: releases are cut from main" >&2
    exit 1
  fi
  gh auth status >/dev/null
fi

BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$ROOT/Resources/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$ROOT/Resources/Info.plist"
echo "==> Version $VERSION ($BUILD_NUMBER)"

echo "==> Building release bundle"
APP="$(CONFIGURATION=release "$ROOT/scripts/build-app.sh" | tail -1)"

if [[ -n "${RELEASE_SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with: $RELEASE_SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$RELEASE_SIGN_IDENTITY" "$APP"
else
  echo "warning: RELEASE_SIGN_IDENTITY not set — bundle keeps the local dev signature." >&2
  echo "         Fine for testing; Gatekeeper will warn users. Set up Developer ID before announcing." >&2
fi

ZIP="$ROOT/dist/Vitrina-$VERSION.zip"
rm -f "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$VERSION/Vitrina-$VERSION.zip"
cat > "$ROOT/dist/appcast.json" <<APPCAST
{
  "latestVersion": "$VERSION",
  "downloadURL": "$DOWNLOAD_URL"
}
APPCAST

echo "==> Artifacts"
echo "    $ZIP"
echo "    sha256: $SHA256"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  git -C "$ROOT" checkout -- Resources/Info.plist
  echo "==> Dry run complete (version stamp reverted)"
  exit 0
fi

echo "==> Tagging and publishing"
git -C "$ROOT" add Resources/Info.plist
git -C "$ROOT" commit -m "Release $VERSION"
git -C "$ROOT" tag "v$VERSION"
git -C "$ROOT" push --follow-tags

gh release create "v$VERSION" "$ZIP" "$ROOT/dist/appcast.json" \
  --repo "$REPO" \
  --title "Vitrina $VERSION" \
  --generate-notes

echo "==> Updating Homebrew tap"
"$ROOT/scripts/update-tap.sh" "$VERSION" "$SHA256" || {
  echo "warning: tap update failed; run manually: scripts/update-tap.sh $VERSION $SHA256" >&2
}

echo "==> Done: https://github.com/$REPO/releases/tag/v$VERSION"
