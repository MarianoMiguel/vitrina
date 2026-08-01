#!/usr/bin/env bash
set -euo pipefail

BUNDLE_IDS=(
  "computer.interstellar.peekportal"
  "dev.mariano.dynamic-share-target"
)

for BUNDLE_ID in "${BUNDLE_IDS[@]}"; do
  tccutil reset Accessibility "$BUNDLE_ID" || true
  tccutil reset ScreenCapture "$BUNDLE_ID" || true
done

echo "Reset Accessibility and Screen Recording decisions for PeekPortal bundle IDs"
