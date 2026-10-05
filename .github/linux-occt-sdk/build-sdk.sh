#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "shared" && "$1" != "static" ) ]]; then
  echo "usage: $0 <shared|static>" >&2
  exit 2
fi

: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${EVENT_SHA:?EVENT_SHA is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
: "${PRODUCER_IMAGE:?PRODUCER_IMAGE is required}"
: "${PRODUCER_IMAGE_TAG:?PRODUCER_IMAGE_TAG is required}"
: "${PRODUCER_IMAGE_DIGEST:?PRODUCER_IMAGE_DIGEST is required}"

linkage="$1"
occt_version="7.9.3"
short_sha="${SOURCE_SHA:0:12}"
sdk_name="opencascade-${occt_version}-linux-x86_64-glibc2.17-${linkage}-${short_sha}"
source_dir="/work/src"
build_dir="/work/build/${linkage}"
stage_parent="/work/stage/${linkage}"
prefix="$stage_parent/$sdk_name"
out_dir="/work/out/${linkage}"
script_dir="/work/automation/.github/linux-occt-sdk"
consumer_pre="/work/consumer-pre/${linkage}"
cmake_version="3.31.6"

find_python() {
  local candidate
  for candidate in \
    /opt/python/cp311-cp311/bin/python \
    /opt/python/cp310-cp310/bin/python \
    /opt/python/cp39-cp39/bin/python \
    /usr/bin/python3; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

python_bin="$(find_python)"
tools_dir="/work/tools/cmake-${cmake_version}"
cmake_bin=""
if command -v cmake >/dev/null 2>&1; then
  cmake_bin="$(command -v cmake)"
  current_cmake="$($cmake_bin --version | sed -n '1s/.* //p')"
  if [[ "$(printf '%s\n%s\n' "3.16" "$current_cmake" | sort -V | head -n1)" != "3.16" ]]; then
    cmake_bin=""
  fi
fi
if [[ -z "$cmake_bin" ]]; then
  if [[ ! -x "$tools_dir/cmake/data/bin/cmake" ]]; then
    rm -rf "$tools_dir"
    mkdir -p "$tools_dir"
    "$python_bin" -m pip install \
      --disable-pip-version-check \
      --no-deps \
      --only-binary=:all: \
      --target "$tools_dir" \
      "cmake==${cmake_version}"
  fi
  cmake_bin="$tools_dir/cmake/data/bin/cmake"
fi
export PATH="$(dirname "$cmake_bin"):$PATH"

for tool in gcc g++ make cmake ld readelf objdump file sha256sum sort; do
  command -v "$tool" >/dev/null || { echo "missing producer tool: $tool" >&2; exit 1; }
done
gcc --version | head -n1
g++ --version | head -n1
cmake --version | head -n1
ld --version | head -n1
readelf --version | head -n1

rm -rf "$build_dir" "$stage_parent" "$consumer_pre" "$out_dir"
mkdir -p "$build_dir" "$stage_parent" "$out_dir"
export SOURCE_DATE_EPOCH

library_type="Shared"
opt_profile="Production"
if [[ "$linkage" == "static" ]]; then
  library_type="Static"
  opt_profile="Default"
fi

cmake_options=(
  "-DCMAKE_BUILD_TYPE=Release"
  "-DCMAKE_C_COMPILER_LAUNCHER=$script_dir/compiler-launcher.sh"
  "-DCMAKE_CXX_COMPILER_LAUNCHER=$script_dir/compiler-launcher.sh"
  "-DBUILD_CPP_STANDARD=C++17"
  "-DBUILD_USE_PCH=OFF"
  "-DBUILD_GTEST=OFF"
  "-DBUILD_Inspector=OFF"
  "-DBUILD_MODULE_FoundationClasses=ON"
  "-DBUILD_MODULE_ModelingData=ON"
  "-DBUILD_MODULE_ModelingAlgorithms=ON"
  "-DBUILD_MODULE_ApplicationFramework=ON"
  "-DBUILD_MODULE_DataExchange=ON"
  "-DBUILD_MODULE_Visualization=OFF"
  "-DBUILD_MODULE_DETools=OFF"
  "-DBUILD_MODULE_Draw=OFF"
  "-DUSE_FREETYPE=OFF"
  "-DUSE_FREEIMAGE=OFF"
  "-DUSE_FFMPEG=OFF"
  "-DUSE_RAPIDJSON=OFF"
  "-DUSE_DRACO=OFF"
  "-DUSE_TBB=OFF"
  "-DUSE_EIGEN=OFF"
  "-DUSE_TCL=OFF"
  "-DUSE_TK=OFF"
  "-DUSE_VTK=OFF"
  "-DUSE_OPENVR=OFF"
  "-DUSE_OPENGL=OFF"
  "-DUSE_GLES2=OFF"
  "-DUSE_XLIB=OFF"
  "-DUSE_D3D=OFF"
  "-DUSE_MMGR_TYPE=NATIVE"
  "-DBUILD_LIBRARY_TYPE=$library_type"
  "-DBUILD_OPT_PROFILE=$opt_profile"
  "-DINSTALL_DIR_LAYOUT=Unix"
  "-DINSTALL_DIR=$prefix"
  "-D3RDPARTY_DIR="
)
printf '%s\n' "${cmake_options[@]}" > "$build_dir/configure-options.txt"
cmake -S "$source_dir" -B "$build_dir" "${cmake_options[@]}"

cmake --build "$build_dir" --parallel 4
cmake --install "$build_dir" --config Release

"$python_bin" - "$prefix/bin/env.sh" <<'PY'
import pathlib
import re
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text, count = re.subn(r'export THIRDPARTY_DIR="[^"]*"', 'export THIRDPARTY_DIR=""', text, count=1)
if count != 1:
    raise SystemExit("failed to normalize THIRDPARTY_DIR in env.sh")
path.write_text(text)
PY

"$python_bin" "$script_dir/sdk_tools.py" validate-prefix --prefix "$prefix" --linkage "$linkage"
"$script_dir/run-consumer.sh" "$prefix" "$consumer_pre" "$linkage"

"$python_bin" "$script_dir/sdk_tools.py" manifest \
  --prefix "$prefix" \
  --consumer "$consumer_pre/occt_sdk_consumer" \
  --consumer-link "$consumer_pre/CMakeFiles/occt_sdk_consumer.dir/link.txt" \
  --cmake-cache "$build_dir/CMakeCache.txt" \
  --configure-options "$build_dir/configure-options.txt" \
  --linkage "$linkage" \
  --source-sha "$SOURCE_SHA" \
  --event-sha "$EVENT_SHA" \
  --source-date-epoch "$SOURCE_DATE_EPOCH" \
  --version "$occt_version" \
  --image "$PRODUCER_IMAGE" \
  --image-tag "$PRODUCER_IMAGE_TAG" \
  --image-digest "$PRODUCER_IMAGE_DIGEST" \
  --output "$prefix/build-manifest.json"
"$python_bin" "$script_dir/sdk_tools.py" validate-prefix --prefix "$prefix" --linkage "$linkage"

archive="$out_dir/$sdk_name.tar.gz"
"$python_bin" "$script_dir/sdk_tools.py" archive \
  --prefix "$prefix" \
  --output "$archive" \
  --source-date-epoch "$SOURCE_DATE_EPOCH"
(
  cd "$out_dir"
  sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
  sha256sum -c "$(basename "$archive").sha256"
)

hidden_stage="/work/stage-hidden-${linkage}"
rm -rf "$hidden_stage"
mv "$stage_parent" "$hidden_stage"

extract_parent="/work/extracted/${linkage}"
rm -rf "$extract_parent"
mkdir -p "$extract_parent"
tar -xzf "$archive" -C "$extract_parent"
extracted_prefix="$extract_parent/$sdk_name"
"$python_bin" "$script_dir/sdk_tools.py" validate-prefix --prefix "$extracted_prefix" --linkage "$linkage"
"$script_dir/run-consumer.sh" "$extracted_prefix" "/work/consumer-post/${linkage}" "$linkage"
"$python_bin" "$script_dir/sdk_tools.py" verify-symbols \
  --prefix "$extracted_prefix" \
  --consumer "/work/consumer-post/${linkage}/occt_sdk_consumer" \
  --manifest "$extracted_prefix/build-manifest.json" \
  --linkage "$linkage"

relocated_parent="/work/relocated/${linkage}"
relocated_prefix="$relocated_parent/$sdk_name"
rm -rf "$relocated_parent"
mkdir -p "$relocated_parent"
mv "$extracted_prefix" "$relocated_prefix"
"$python_bin" "$script_dir/sdk_tools.py" validate-prefix --prefix "$relocated_prefix" --linkage "$linkage"
"$script_dir/run-consumer.sh" "$relocated_prefix" "/work/consumer-relocated/${linkage}" "$linkage"
"$python_bin" "$script_dir/sdk_tools.py" verify-symbols \
  --prefix "$relocated_prefix" \
  --consumer "/work/consumer-relocated/${linkage}/occt_sdk_consumer" \
  --manifest "$relocated_prefix/build-manifest.json" \
  --linkage "$linkage"

echo "SDK_ARCHIVE=$archive"
