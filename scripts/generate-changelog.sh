#!/bin/sh
set -eu

tag="${1:-${GITHUB_REF_NAME:-}}"
if [ -z "$tag" ]; then
  tag="Unreleased"
fi

previous_tag="$(git describe --tags --abbrev=0 "${tag}^{commit}^" 2>/dev/null || git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
range=""
if [ -n "$previous_tag" ] && [ "$tag" != "Unreleased" ]; then
  range="$previous_tag..$tag"
elif [ -n "$previous_tag" ]; then
  range="$previous_tag..HEAD"
fi

date_utc="$(date -u +%Y-%m-%d)"

{
  printf '## %s - %s\n\n' "$tag" "$date_utc"
  if [ -n "$range" ]; then
    git log --no-merges --format='- %s (%h)' "$range"
  else
    git log --no-merges --format='- %s (%h)'
  fi
  printf '\n'
} > RELEASE_NOTES.md

if [ -f CHANGELOG.md ]; then
  tmp="$(mktemp)"
  {
    printf '# Changelog\n\n'
    cat RELEASE_NOTES.md
    awk 'NR > 2 { print }' CHANGELOG.md
  } > "$tmp"
  mv "$tmp" CHANGELOG.md
else
  {
    printf '# Changelog\n\n'
    cat RELEASE_NOTES.md
  } > CHANGELOG.md
fi
