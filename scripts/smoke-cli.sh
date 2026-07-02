#!/bin/sh
set -eu

bin="${XCODE_STORAGE_BIN:-.build/debug/xcode-storage}"
if [ ! -x "$bin" ]; then
  swift build >/dev/null
fi

tmp_parent="${TMPDIR:-/tmp}"
tmp_parent="${tmp_parent%/}"
tmp="$tmp_parent/xcode-storage-cli-smoke.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

require_output() {
  description="$1"
  expected="$2"
  output="$3"
  if ! printf '%s' "$output" | grep -F "$expected" >/dev/null; then
    echo "missing expected output for $description: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

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

output="$("$bin" init --root "$tmp/External Disk" --dry-run --no-create-images)"
require_output "init dry-run" "mkdir -p '$tmp/External Disk/Xcode'" "$output"

output="$("$bin" daemon install --root "$tmp/External Disk" --home "$tmp/Home" --dry-run)"
require_output "daemon install dry-run" "write /Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist" "$output"

output="$("$bin" launchd install --root "$tmp/External Disk" --home "$tmp/Home" --dry-run)"
require_output "launchd install dry-run" "write /Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist" "$output"

output="$("$bin" native install --root "$tmp/External Disk" --home "$tmp/Home" --scope user --dry-run)"
require_output "native user install dry-run" "DerivedData.sparsebundle" "$output"
require_output "native user install dry-run" "$tmp/Home/Library/Developer/Xcode/DerivedData" "$output"

if "$bin" native install --root "$tmp/External Disk" --home "$tmp/Home" --scope system --dry-run >"$tmp/native-system.out" 2>"$tmp/native-system.err"; then
  output="$(cat "$tmp/native-system.out")"
  require_output "native system install dry-run" "/Library/Developer/CoreSimulator/Images" "$output"
  require_output "native system install dry-run" "chmod 1777" "$output"
else
  grep -F "native mountpoint is already mounted from a different backend" "$tmp/native-system.err" >/dev/null
fi

if "$bin" doctor --root "$tmp/missing-root" --skip-simctl --json >"$tmp/doctor.json" 2>"$tmp/doctor.err"; then
  echo "expected doctor to fail for missing root" >&2
  exit 1
fi

ruby -rjson -e '
  report = JSON.parse(File.read(ARGV.fetch(0)))
  checks = report.fetch("checks")
  abort "expected at least one failed doctor check" unless checks.any? { |check| check.fetch("status") == "FAIL" }
' "$tmp/doctor.json"
