#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <release-assets-dir>" >&2
  exit 2
fi
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${WINDOWS_SHA256:?WINDOWS_SHA256 is required}"

asset_root="$(cd "$1" && pwd)"
linux_dir="$asset_root/linux"
macos_dir="$asset_root/macos"
windows_dir="$asset_root/windows"

test -d "$linux_dir"
test -d "$macos_dir"
test -d "$windows_dir"

SOURCE_SHA="$SOURCE_SHA" bash .github/linux-occt-sdk/verify-release-assets.sh "$linux_dir"
SOURCE_SHA="$SOURCE_SHA" bash .github/macos-occt-sdk/verify-release-assets.sh "$macos_dir"

windows_name="opencascade-7.9.3-vc14-64-combined.zip"
windows_archive="$windows_dir/$windows_name"
windows_checksum="$windows_archive.sha256"
test -f "$windows_archive"
test -f "$windows_checksum"

windows_count="$(find "$windows_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [[ "$windows_count" != "2" ]]; then
  echo "expected exactly 2 Windows release assets, found $windows_count" >&2
  find "$windows_dir" -maxdepth 1 -type f -print >&2
  exit 1
fi

(cd "$windows_dir" && sha256sum -c "$(basename "$windows_checksum")")
actual_windows_sha="$(sha256sum "$windows_archive" | awk '{print $1}')"
test "$actual_windows_sha" = "$WINDOWS_SHA256"

total_count="$(find "$asset_root" -type f | wc -l | tr -d ' ')"
if [[ "$total_count" != "14" ]]; then
  echo "expected exactly 14 combined release assets, found $total_count" >&2
  find "$asset_root" -type f -print >&2
  exit 1
fi
