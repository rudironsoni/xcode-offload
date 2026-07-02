#!/bin/sh
set -eu

tag="${1:-v9.8.7-test.1}"
version="${tag#v}"

archive="$(XCODE_STORAGE_RELEASE_TAG="$tag" scripts/build-release.sh)"
archive_name="$(basename "$archive")"
checksum="$archive.sha256"

expected="xcode-storage-$version-macos-arm64.tar.gz"
if [ "$archive_name" != "$expected" ]; then
  echo "unexpected archive name: $archive_name, expected $expected" >&2
  exit 1
fi

tmp="${TMPDIR:-/tmp}/xcode-storage-release-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

cp "$archive" "$checksum" "$tmp/"
(
  cd "$tmp"
  shasum -a 256 -c "$expected.sha256"
  tar -tzf "$expected" | grep -F "xcode-storage" >/dev/null
)

