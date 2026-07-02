#!/bin/sh
set -eu

bin="${XCODE_STORAGE_BIN:-.build/debug/xcode-storage}"
if [ ! -x "$bin" ]; then
  swift build >/dev/null
fi

tmp="${TMPDIR:-/tmp}/xcode-storage-cli-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

expect_failure() {
  if "$@" >"$tmp/stdout" 2>"$tmp/stderr"; then
    echo "expected failure: $*" >&2
    exit 1
  fi
}

"$bin" help | grep -F "xcode-storage manages external Xcode" >/dev/null
"$bin" version | grep -E '^xcode-storage |^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null

expect_failure "$bin" definitely-not-a-command
grep -F "unknown command: definitely-not-a-command" "$tmp/stderr" >/dev/null

expect_failure "$bin" sim recreate --name SmokeOnly --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17
grep -F "missing required option: --runtime" "$tmp/stderr" >/dev/null

"$bin" init --root "$tmp/External Disk" --dry-run --no-create-images \
  | grep -F "mkdir -p '$tmp/External Disk/Xcode'" >/dev/null

"$bin" daemon install --root "$tmp/External Disk" --home "$tmp/Home" --dry-run \
  | grep -F "write /Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist" >/dev/null

"$bin" launchd install --root "$tmp/External Disk" --home "$tmp/Home" --dry-run \
  | grep -F "write /Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist" >/dev/null

if "$bin" doctor --root "$tmp/missing-root" --skip-simctl --json >"$tmp/doctor.json" 2>"$tmp/doctor.err"; then
  echo "expected doctor to fail for missing root" >&2
  exit 1
fi

ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  checks = report.fetch("checks")
  abort "expected at least one failed doctor check" unless checks.any? { |check| check.fetch("status") == "FAIL" }
' "$tmp/doctor.json"

