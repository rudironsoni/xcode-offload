#!/bin/sh
set -eu

output="${1:-Sources/XcodeStorageCore/Generated/GeneratedBuildMetadata.swift}"
mkdir -p "$(dirname "$output")"

tag="${GITHUB_REF_NAME:-}"
if [ -z "$tag" ]; then
  tag="$(git describe --tags --exact-match 2>/dev/null || true)"
fi

semver_pattern='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if printf '%s' "$tag" | grep -Eq "$semver_pattern"; then
  version="${tag#v}"
else
  base="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
  if [ -z "$base" ]; then
    base="0.1.0"
  fi
  count="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
  short="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  version="$base-dev.$count+$short"
fi

commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
dirty="false"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  dirty="true"
fi

cat > "$output" <<EOF
public enum GeneratedBuildMetadata {
    public static let version = "$version"
    public static let commit = "$commit"
    public static let buildDate = "$build_date"
    public static let dirty = $dirty
}
EOF

printf '%s\n' "$version"
