#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <release-assets-dir>" >&2
  exit 2
fi
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${WORKFLOW_SHA:?WORKFLOW_SHA is required}"
: "${OCCT_VERSION:?OCCT_VERSION is required}"

asset_root="$(cd "$1" && pwd)"
short_sha="${SOURCE_SHA:0:12}"
version="$OCCT_VERSION"
prefix="opencascade-${version}-linux-x86_64-glibc2.17"
root_toolkits='["TKDESTEP","TKDEIGES","TKDESTL","TKOffset","TKMesh"]'
expected_toolkits='["TKDESTEP","TKDE","TKBRep","TKernel","TKMath","TKXSBase","TKTopAlgo","TKG2d","TKCAF","TKCDF","TKLCAF","TKG3d","TKXCAF","TKShHealing","TKGeomBase","TKGeomAlgo","TKBO","TKPrim","TKService","TKV3d","TKVCAF","TKMesh","TKHLR","TKDEIGES","TKBool","TKDESTL","TKOffset","TKFillet"]'
expected_toolkits_sorted="$(jq -c 'sort' <<<"$expected_toolkits")"

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
  expected="$(awk '{print $1}' "$checksum" | tr -d '\r')"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  test "$expected" = "$actual"
  manifest="$(tar -xOzf "$archive" --wildcards '*/build-manifest.json')"
  test "$(jq -r '.occt.commit' <<<"$manifest")" = "$SOURCE_SHA"
  test "$(jq -r '.occt.event_sha' <<<"$manifest")" = "$WORKFLOW_SHA"
  test "$(jq -r '.occt.version' <<<"$manifest")" = "$version"
  test "$(jq -r '.producer.architecture' <<<"$manifest")" = "x86_64"
  test "$(jq -r '.producer.glibc_baseline' <<<"$manifest")" = "2.17"
  test "$(jq -r '.linkage' <<<"$manifest")" = "$linkage"
  test "$(jq -c '.requested_modules' <<<"$manifest")" = "[]"
  test "$(jq -c '.requested_toolkits' <<<"$manifest")" = "$root_toolkits"
  test "$(jq -c '.expected_toolkits' <<<"$manifest")" = "$expected_toolkits"
  test "$(jq -c '.toolkits | sort' <<<"$manifest")" = "$expected_toolkits_sorted"
  test "$(jq -c '.exported_toolkits | sort' <<<"$manifest")" = "$expected_toolkits_sorted"
done
