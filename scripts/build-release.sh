#!/bin/sh
set -eu

product="xcode-storage"
configuration="release"
artifact_dir=".build/artifacts"

version="$(scripts/generate-version-source.sh)"
swift build -c "$configuration" --product "$product"

mkdir -p "$artifact_dir"
binary=".build/release/$product"
archive="$artifact_dir/$product-$version-macos-arm64.tar.gz"

tar -czf "$archive" -C "$(dirname "$binary")" "$product"
shasum -a 256 "$archive" > "$archive.sha256"

printf '%s\n' "$archive"
