#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <sdk-prefix> <build-dir> <shared|static> <arm64|x86_64>" >&2
  exit 2
fi

prefix="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
build_dir="$2"
linkage="$3"
architecture="$4"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
consumer_src="$script_dir/consumer"

case "$linkage" in shared|static) ;; *) exit 2 ;; esac
case "$architecture" in arm64|x86_64) ;; *) exit 2 ;; esac

rm -rf "$build_dir"
mkdir -p "$build_dir"
shared_flag=OFF
if [[ "$linkage" == "shared" ]]; then
  shared_flag=ON
fi

cmake \
  -G "Unix Makefiles" \
  -S "$consumer_src" \
  -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
  -DCMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY=ON \
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
  -DOpenCASCADE_DIR="$prefix/lib/cmake/opencascade" \
  -DOCCT_SDK_SHARED="$shared_flag"

expected_dir="$prefix/lib/cmake/opencascade"
configured_dir="$(sed -n 's/^OpenCASCADE_DIR:[^=]*=//p' "$build_dir/CMakeCache.txt")"
if [[ "$configured_dir" != "$expected_dir" ]]; then
  echo "OpenCASCADE_DIR resolved to $configured_dir, expected $expected_dir" >&2
  exit 1
fi

cmake --build "$build_dir" --parallel --verbose
consumer="$build_dir/occt_sdk_consumer"
test -x "$consumer"
link_command="$build_dir/CMakeFiles/occt_sdk_consumer.dir/link.txt"
test -f "$link_command"

python3 "$script_dir/sdk_tools.py" verify-consumer \
  --prefix "$prefix" \
  --consumer "$consumer" \
  --link-command "$link_command" \
  --cmake-cache "$build_dir/CMakeCache.txt" \
  --linkage "$linkage" \
  --architecture "$architecture" \
  --deployment-target 13.0

resource_dir="$(tr -d '\r\n' < "$build_dir/opencascade-resource-dir.txt")"
if [[ "$resource_dir" != "$prefix/share/opencascade/resources" ]]; then
  echo "OpenCASCADE_RESOURCE_DIR resolved to $resource_dir" >&2
  exit 1
fi
test -f "$resource_dir/XSTEPResource/STEP"
test -f "$resource_dir/XSMessage/XSTEP.us"
(
  unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH CASROOT THIRDPARTY_DIR CSF_STEPUserDefaults
  export CSF_STEPDefaults="$resource_dir/XSTEPResource"
  export CSF_XSMessage="$resource_dir/XSMessage"
  cd "$build_dir"
  "$consumer"
)
