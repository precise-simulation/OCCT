#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <release-assets-dir>" >&2
  exit 2
fi
: "${SOURCE_SHA:?SOURCE_SHA is required}"

asset_root="$(cd "$1" && pwd)"
short_sha="${SOURCE_SHA:0:12}"
version="7.9.3"
prefix="opencascade-${version}-linux-x86_64-glibc2.17"

actual_count="$(find "$asset_root" -type f | wc -l | tr -d ' ')"
if [[ "$actual_count" != "4" ]]; then
  echo "expected exactly 4 release assets, found $actual_count" >&2
  find "$asset_root" -type f -print >&2
  exit 1
fi

for linkage in shared static; do
  archive_name="$prefix-$linkage-$short_sha.tar.gz"
  archive="$asset_root/$archive_name"
  checksum="$archive.sha256"
  test -f "$archive"
  test -f "$checksum"
  (cd "$asset_root" && sha256sum -c "$(basename "$checksum")")
  manifest="$(tar -xOzf "$archive" --wildcards '*/build-manifest.json')"
  test "$(jq -r '.occt.commit' <<<"$manifest")" = "$SOURCE_SHA"
  test "$(jq -r '.occt.version' <<<"$manifest")" = "$version"
  test "$(jq -r '.producer.architecture' <<<"$manifest")" = "x86_64"
  test "$(jq -r '.producer.glibc_baseline' <<<"$manifest")" = "2.17"
  test "$(jq -r '.linkage' <<<"$manifest")" = "$linkage"
done
