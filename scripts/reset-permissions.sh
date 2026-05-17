#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.mariano.dynamic-share-target"

tccutil reset Accessibility "$BUNDLE_ID" || true
tccutil reset ScreenCapture "$BUNDLE_ID" || true

echo "Reset Accessibility and Screen Recording decisions for $BUNDLE_ID"
