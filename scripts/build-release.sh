#!/bin/sh
set -eu

product="xcode-storage"
configuration="release"
artifact_dir=".build/artifacts"
metadata="Sources/XcodeStorageCore/Generated/GeneratedBuildMetadata.swift"
metadata_backup=""

cleanup() {
  if [ -n "$metadata_backup" ] && [ -f "$metadata_backup" ]; then
    cp "$metadata_backup" "$metadata"
    rm -f "$metadata_backup"
  fi
}

if [ "${XCODE_STORAGE_KEEP_GENERATED_VERSION:-0}" != "1" ] && [ -f "$metadata" ]; then
  metadata_backup="$(mktemp)"
  cp "$metadata" "$metadata_backup"
  trap cleanup EXIT INT TERM
fi

version="$(scripts/generate-version-source.sh "$metadata")"
swift build -c "$configuration" --product "$product" >&2

mkdir -p "$artifact_dir"
binary=".build/release/$product"
archive="$artifact_dir/$product-$version-macos-arm64.tar.gz"

tar -czf "$archive" -C "$(dirname "$binary")" "$product"
shasum -a 256 "$archive" > "$archive.sha256"

printf '%s\n' "$archive"
