#!/bin/sh
set -eu

required_pages="
docs/index.html
docs/install.html
docs/concepts.html
docs/commands.html
docs/operations.html
docs/troubleshooting.html
docs/release.html
docs/assets/styles.css
"

for page in $required_pages; do
  if [ ! -f "$page" ]; then
    echo "missing docs file: $page" >&2
    exit 1
  fi
done

em_dash=$(printf '\342\200\224')
en_dash=$(printf '\342\200\223')

if git grep -nE '\\.build/debug|swift build|git clone|Build from source|native|Native|certify|Certify|certification|Certification|XCODE_STORAGE_CERT|--cert-root' -- README.md docs; then
  echo "docs contain build artifact paths, source-build setup, stale command names, or disallowed dash characters" >&2
  exit 1
fi

if git grep -n "$em_dash" -- README.md docs || git grep -n "$en_dash" -- README.md docs; then
  echo "docs contain disallowed dash characters" >&2
  exit 1
fi

if git grep -n '`' -- docs/*.html; then
  echo "HTML docs contain Markdown backticks; use <code> instead" >&2
  exit 1
fi

for page in docs/*.html; do
  grep -F '<!doctype html>' "$page" >/dev/null
  grep -F '<html lang="en">' "$page" >/dev/null
  grep -F '<main class="layout">' "$page" >/dev/null
  grep -F '<meta name="viewport"' "$page" >/dev/null
  grep -F 'assets/styles.css' "$page" >/dev/null
  grep -F 'Docs for <code>xcode-storage</code>' "$page" >/dev/null
done

grep -F 'https://rudironsoni.github.io/xcode-storage/' README.md >/dev/null
grep -F 'xcode-storage mounts verify' docs/commands.html >/dev/null
grep -F 'The examples below assume the installed command is available as <code>xcode-storage</code>' docs/install.html >/dev/null
