#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <release-assets-dir>" >&2
  exit 2
fi
: "${SOURCE_SHA:?SOURCE_SHA is required}"

asset_root="$(cd "$1" && pwd)"
short_sha="${SOURCE_SHA:0:12}"
version="8.0.1"
prefix="opencascade-$version-macos13"

expected_specs=(
  "x86_64 shared"
  "x86_64 static"
  "arm64 shared"
  "arm64 static"
)

actual_count="$(find "$asset_root" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [[ "$actual_count" != "8" ]]; then
  echo "expected exactly 8 release assets, found $actual_count" >&2
  find "$asset_root" -maxdepth 1 -type f -print >&2
  exit 1
fi

for spec in "${expected_specs[@]}"; do
  read -r architecture linkage <<<"$spec"
  archive_name="$prefix-$architecture-$linkage-$short_sha.tar.gz"
  archive="$asset_root/$archive_name"
  checksum="$archive.sha256"
  test -f "$archive"
  test -f "$checksum"
  expected="$(awk '{print $1}' "$checksum" | tr -d '\r')"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  test "$expected" = "$actual"
  manifest="$(tar -xOzf "$archive" --wildcards '*/build-manifest.json')"
  test "$(jq -r '.occt.commit' <<<"$manifest")" = "$SOURCE_SHA"
  test "$(jq -r '.occt.version' <<<"$manifest")" = "$version"
  test "$(jq -r '.artifact.architecture' <<<"$manifest")" = "$architecture"
  test "$(jq -r '.artifact.deployment_target' <<<"$manifest")" = "13.0"
  test "$(jq -r '.linkage' <<<"$manifest")" = "$linkage"
done
