#!/bin/sh
set -eu

patterns='/Volumes/1TB|F0F5B9A5|EXTERNAL_SSD_|com\.rudironsoni|rudironsoni-xcode|xcode-mount-coresimulator-caches|xcode-simulator-device-store'

if git grep -nE "$patterns" -- README.md Sources Tests .github scripts ':!scripts/check-no-machine-defaults.sh'; then
  echo "machine-specific storage defaults or legacy labels found" >&2
  exit 1
fi
