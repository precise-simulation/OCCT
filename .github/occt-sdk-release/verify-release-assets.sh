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

windows_name="occt-combined-release-no-pch.zip"
windows_archive="$windows_dir/$windows_name"
windows_checksum="$windows_archive.sha256"
test -f "$windows_archive"
test -f "$windows_checksum"

static_name="opencascade-8.0.1-windows-x86_64-vc143-static-lean-${SOURCE_SHA:0:12}.zip"
static_archive="$windows_dir/$static_name"
static_checksum="$static_archive.sha256"
test -f "$static_archive"
test -f "$static_checksum"

windows_count="$(find "$windows_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [[ "$windows_count" != "4" ]]; then
  echo "expected exactly 4 Windows release assets, found $windows_count" >&2
  find "$windows_dir" -maxdepth 1 -type f -print >&2
  exit 1
fi

(cd "$windows_dir" && sha256sum -c "$(basename "$windows_checksum")")
actual_windows_sha="$(sha256sum "$windows_archive" | awk '{print $1}')"
test "$actual_windows_sha" = "$WINDOWS_SHA256"
(cd "$windows_dir" && sha256sum -c "$(basename "$static_checksum")")

static_manifest="$(unzip -p "$static_archive" '*/sdk-manifest.txt' | tr -d '\r')"
grep -Fqx "occt-version=8.0.1" <<<"$static_manifest"
grep -Fqx "occt-source-sha=$SOURCE_SHA" <<<"$static_manifest"
grep -Fqx "platform=windows-x86_64" <<<"$static_manifest"
grep -Fqx "msvc-toolset=vc143" <<<"$static_manifest"
grep -Fqx "linkage=static" <<<"$static_manifest"
grep -Fqx "profile=lean" <<<"$static_manifest"
grep -Fqx "toolkit-count=28" <<<"$static_manifest"
grep -Fqx "consumer-definitions=OCCT_STATIC_BUILD;OCCT_NO_PLUGINS" <<<"$static_manifest"
grep -Fqx "consumer-system-libs=advapi32;gdi32;user32;wsock32;psapi;windowscodecs;winmm" <<<"$static_manifest"

static_lib_count="$(unzip -Z1 "$static_archive" | grep -Eic '\.lib$')"
test "$static_lib_count" = "28"
if unzip -Z1 "$static_archive" | grep -Eiq '\.dll$'; then
  echo "static Windows SDK unexpectedly contains DLLs" >&2
  exit 1
fi

total_count="$(find "$asset_root" -type f | wc -l | tr -d ' ')"
if [[ "$total_count" != "16" ]]; then
  echo "expected exactly 16 combined release assets, found $total_count" >&2
  find "$asset_root" -type f -print >&2
  exit 1
fi
