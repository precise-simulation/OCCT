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
linux_dir="$asset_root/linux"
macos_dir="$asset_root/macos"
windows_dir="$asset_root/windows"

test -d "$linux_dir"
test -d "$macos_dir"
test -d "$windows_dir"

SOURCE_SHA="$SOURCE_SHA" WORKFLOW_SHA="$WORKFLOW_SHA" OCCT_VERSION="$OCCT_VERSION" bash .github/linux-occt-sdk/verify-release-assets.sh "$linux_dir"
SOURCE_SHA="$SOURCE_SHA" WORKFLOW_SHA="$WORKFLOW_SHA" OCCT_VERSION="$OCCT_VERSION" bash .github/macos-occt-sdk/verify-release-assets.sh "$macos_dir"

shared_name="opencascade-${OCCT_VERSION}-windows-x86_64-vc143-shared-lean-${SOURCE_SHA:0:12}.zip"
shared_archive="$windows_dir/$shared_name"
shared_checksum="$shared_archive.sha256"
test -f "$shared_archive"
test -f "$shared_checksum"

static_name="opencascade-${OCCT_VERSION}-windows-x86_64-vc143-static-lean-${SOURCE_SHA:0:12}.zip"
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

(cd "$windows_dir" && sha256sum -c "$(basename "$shared_checksum")")
(cd "$windows_dir" && sha256sum -c "$(basename "$static_checksum")")

shared_manifest="$(unzip -p "$shared_archive" '*/sdk-manifest.txt' | tr -d '\r')"
grep -Fqx "occt-version=$OCCT_VERSION" <<<"$shared_manifest"
grep -Fqx "occt-source-sha=$SOURCE_SHA" <<<"$shared_manifest"
grep -Fqx "workflow-sha=$WORKFLOW_SHA" <<<"$shared_manifest"
grep -Fqx "platform=windows-x86_64" <<<"$shared_manifest"
grep -Fqx "msvc-toolset=vc143" <<<"$shared_manifest"
grep -Fqx "msvc-runtime=MultiThreadedDLL" <<<"$shared_manifest"
grep -Fqx "linkage=shared" <<<"$shared_manifest"
grep -Fqx "profile=lean" <<<"$shared_manifest"
grep -Fqx "build-opt-profile=Production" <<<"$shared_manifest"
grep -Fqx "optional-third-party=none" <<<"$shared_manifest"
grep -Fqx "toolkit-count=28" <<<"$shared_manifest"
if grep -Eq '^consumer-(definitions|system-libs)=' <<<"$shared_manifest"; then
  echo "lean shared Windows SDK unexpectedly declares static consumer settings" >&2
  exit 1
fi

expected_toolkits="$(cat <<'EOF'
TKDESTEP
TKDE
TKBRep
TKernel
TKMath
TKXSBase
TKTopAlgo
TKG2d
TKCAF
TKCDF
TKLCAF
TKG3d
TKXCAF
TKShHealing
TKGeomBase
TKGeomAlgo
TKBO
TKPrim
TKService
TKV3d
TKVCAF
TKMesh
TKHLR
TKDEIGES
TKBool
TKDESTL
TKOffset
TKFillet
EOF
)"

shared_toolkits="$(sed -n 's/^toolkits=//p' <<<"$shared_manifest" | tr ',' '\n' | sort)"
diff -u <(sort <<<"$expected_toolkits") <(printf '%s\n' "$shared_toolkits")
shared_archive_toolkits="$(unzip -Z1 "$shared_archive" | sed -nE 's#^.*/(TK[A-Za-z0-9_]*)\.dll$#\1#p' | sort)"
diff -u <(sort <<<"$expected_toolkits") <(printf '%s\n' "$shared_archive_toolkits")
shared_import_toolkits="$(unzip -Z1 "$shared_archive" | sed -nE 's#^.*/(TK[A-Za-z0-9_]*)\.lib$#\1#p' | sort)"
diff -u <(sort <<<"$expected_toolkits") <(printf '%s\n' "$shared_import_toolkits")

shared_dll_count="$(unzip -Z1 "$shared_archive" | grep -Eic '/TK[A-Za-z0-9_]*\.dll$')"
shared_lib_count="$(unzip -Z1 "$shared_archive" | grep -Eic '/TK[A-Za-z0-9_]*\.lib$')"
shared_all_dll_count="$(unzip -Z1 "$shared_archive" | grep -Eic '\.dll$')"
shared_all_lib_count="$(unzip -Z1 "$shared_archive" | grep -Eic '\.lib$')"
test "$shared_dll_count" = "28"
test "$shared_lib_count" = "28"
test "$shared_all_dll_count" = "28"
test "$shared_all_lib_count" = "28"

static_manifest="$(unzip -p "$static_archive" '*/sdk-manifest.txt' | tr -d '\r')"
grep -Fqx "occt-version=$OCCT_VERSION" <<<"$static_manifest"
grep -Fqx "occt-source-sha=$SOURCE_SHA" <<<"$static_manifest"
grep -Fqx "workflow-sha=$WORKFLOW_SHA" <<<"$static_manifest"
grep -Fqx "platform=windows-x86_64" <<<"$static_manifest"
grep -Fqx "msvc-toolset=vc143" <<<"$static_manifest"
grep -Fqx "msvc-runtime=MultiThreadedDLL" <<<"$static_manifest"
grep -Fqx "linkage=static" <<<"$static_manifest"
grep -Fqx "profile=lean" <<<"$static_manifest"
grep -Fqx "optional-third-party=none" <<<"$static_manifest"
grep -Fqx "toolkit-count=28" <<<"$static_manifest"
grep -Fqx "consumer-definitions=OCCT_STATIC_BUILD;OCCT_NO_PLUGINS" <<<"$static_manifest"
grep -Fqx "consumer-system-libs=advapi32;gdi32;user32;wsock32;psapi;windowscodecs;winmm" <<<"$static_manifest"

static_toolkits="$(sed -n 's/^toolkits=//p' <<<"$static_manifest" | tr ',' '\n' | sort)"
diff -u <(sort <<<"$expected_toolkits") <(printf '%s\n' "$static_toolkits")
static_archive_toolkits="$(unzip -Z1 "$static_archive" | sed -nE 's#^.*/(TK[A-Za-z0-9_]*)\.lib$#\1#p' | sort)"
diff -u <(sort <<<"$expected_toolkits") <(printf '%s\n' "$static_archive_toolkits")

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
