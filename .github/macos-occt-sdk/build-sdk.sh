#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <arm64|x86_64> <shared|static> <runner-label>" >&2
  exit 2
fi

architecture="$1"
linkage="$2"
runner_label="$3"
case "$architecture" in arm64|x86_64) ;; *) exit 2 ;; esac
case "$linkage" in shared|static) ;; *) exit 2 ;; esac

: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${EVENT_SHA:?EVENT_SHA is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
: "${OCCT_AUTOMATION_DIR:?OCCT_AUTOMATION_DIR is required}"
: "${OCCT_SOURCE_DIR:?OCCT_SOURCE_DIR is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${DEVELOPER_DIR:?DEVELOPER_DIR is required}"
: "${OCCT_CLANG:?OCCT_CLANG is required}"
: "${OCCT_CLANGXX:?OCCT_CLANGXX is required}"
: "${OCCT_MACOS_SDK:?OCCT_MACOS_SDK is required}"

occt_version="8.0.1"
deployment_target="13.0"
short_sha="${SOURCE_SHA:0:12}"
sdk_name="opencascade-${occt_version}-macos13-${architecture}-${linkage}-${short_sha}"
script_dir="$OCCT_AUTOMATION_DIR/.github/macos-occt-sdk"
source_dir="$OCCT_SOURCE_DIR"
work_root="$RUNNER_TEMP/occt-macos-sdk/$architecture/$linkage"
build_dir="$work_root/build"
stage_parent="$work_root/stage"
prefix="$stage_parent/$sdk_name"
consumer_pre="$work_root/consumer-pre"
out_dir="$RUNNER_TEMP/occt-macos-sdk-out/$architecture/$linkage"
framework_record="$build_dir/framework-normalization.json"

rm -rf "$work_root" "$out_dir"
mkdir -p "$build_dir" "$stage_parent" "$out_dir"
export SOURCE_DATE_EPOCH COPYFILE_DISABLE=1

library_type="Shared"
if [[ "$linkage" == "static" ]]; then
  library_type="Static"
fi

cmake_options=(
  "-DCMAKE_BUILD_TYPE=Release"
  "-DCMAKE_OSX_DEPLOYMENT_TARGET=$deployment_target"
  "-DCMAKE_OSX_ARCHITECTURES=$architecture"
  "-DCMAKE_OSX_SYSROOT=$OCCT_MACOS_SDK"
  "-DCMAKE_C_COMPILER=$OCCT_CLANG"
  "-DCMAKE_CXX_COMPILER=$OCCT_CLANGXX"
  "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON"
  "-DINSTALL_DIR=$prefix"
  "-DINSTALL_DIR_LAYOUT=Unix"
  "-DINSTALL_DIR_WITH_VERSION=OFF"
  "-DBUILD_CPP_STANDARD=C++17"
  "-DBUILD_USE_VCPKG=OFF"
  "-DBUILD_USE_PCH=OFF"
  "-DBUILD_Inspector=OFF"
  "-DBUILD_SOVERSION_NUMBERS=2"
  "-DBUILD_MODULE_FoundationClasses=ON"
  "-DBUILD_MODULE_ModelingData=ON"
  "-DBUILD_MODULE_ModelingAlgorithms=ON"
  "-DBUILD_MODULE_ApplicationFramework=ON"
  "-DBUILD_MODULE_DataExchange=ON"
  "-DBUILD_MODULE_Visualization=OFF"
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
  "-DUSE_MMGR_TYPE=NATIVE"
  "-DBUILD_LIBRARY_TYPE=$library_type"
  "-D3RDPARTY_DIR="
)
if [[ "$linkage" == "shared" ]]; then
  cmake_options+=("-DBUILD_OPT_PROFILE=Production" "-DINSTALL_NAME_DIR=@rpath")
fi

printf '%s\n' "${cmake_options[@]}" > "$build_dir/configure-options.txt"
cmake -G "Unix Makefiles" -S "$source_dir" -B "$build_dir" "${cmake_options[@]}"

cache_arch="$(sed -n 's/^CMAKE_OSX_ARCHITECTURES:STRING=//p' "$build_dir/CMakeCache.txt")"
cache_target="$(sed -n 's/^CMAKE_OSX_DEPLOYMENT_TARGET:[^=]*=//p' "$build_dir/CMakeCache.txt")"
cache_sysroot="$(sed -n 's/^CMAKE_OSX_SYSROOT:[^=]*=//p' "$build_dir/CMakeCache.txt")"
if [[ "$cache_arch" != "$architecture" || "$cache_target" != "$deployment_target" || "$cache_sysroot" != "$OCCT_MACOS_SDK" ]]; then
  echo "configured architecture/deployment target/sysroot mismatch: $cache_arch / $cache_target / $cache_sysroot" >&2
  exit 1
fi

parallel="$(sysctl -n hw.logicalcpu)"
cmake --build "$build_dir" --parallel "$parallel"
cmake --install "$build_dir" --config Release

python3 "$script_dir/sdk_tools.py" normalize-env --path "$prefix/bin/env.sh"
if [[ "$linkage" == "static" ]]; then
  python3 "$script_dir/sdk_tools.py" normalize-static-frameworks \
    --prefix "$prefix" \
    --sdk-path "$OCCT_MACOS_SDK" \
    --record "$framework_record"
fi

forbidden=(
  "$OCCT_AUTOMATION_DIR"
  "$source_dir"
  "$build_dir"
  "$stage_parent"
  "$consumer_pre"
  "$DEVELOPER_DIR"
  "$OCCT_MACOS_SDK"
  "/Users/runner/"
)
validate_args=()
manifest_forbidden=()
for path in "${forbidden[@]}"; do
  validate_args+=(--forbidden-path "$path")
  manifest_forbidden+=(--forbidden-path "$path")
done

python3 "$script_dir/sdk_tools.py" validate-prefix \
  --prefix "$prefix" \
  --linkage "$linkage" \
  --architecture "$architecture" \
  --deployment-target "$deployment_target" \
  "${validate_args[@]}"

bash "$script_dir/run-consumer.sh" "$prefix" "$consumer_pre" "$linkage" "$architecture"

manifest_args=(
  --prefix "$prefix"
  --consumer "$consumer_pre/occt_sdk_consumer"
  --consumer-link "$consumer_pre/CMakeFiles/occt_sdk_consumer.dir/link.txt"
  --cmake-cache "$build_dir/CMakeCache.txt"
  --configure-options "$build_dir/configure-options.txt"
  --linkage "$linkage"
  --architecture "$architecture"
  --deployment-target "$deployment_target"
  --source-sha "$SOURCE_SHA"
  --event-sha "$EVENT_SHA"
  --source-date-epoch "$SOURCE_DATE_EPOCH"
  --version "$occt_version"
  --runner-label "$runner_label"
  --developer-dir "$DEVELOPER_DIR"
  --sdk-path "$OCCT_MACOS_SDK"
  --clang "$OCCT_CLANG"
  --clangxx "$OCCT_CLANGXX"
  --generator "Unix Makefiles"
  "${manifest_forbidden[@]}"
  --output "$prefix/build-manifest.json"
)
if [[ "$linkage" == "static" ]]; then
  manifest_args+=(--framework-normalization "$framework_record")
fi
python3 "$script_dir/sdk_tools.py" thin-manifest "${manifest_args[@]}"

python3 "$script_dir/sdk_tools.py" validate-prefix \
  --prefix "$prefix" \
  --linkage "$linkage" \
  --architecture "$architecture" \
  --deployment-target "$deployment_target"

archive="$out_dir/$sdk_name.tar.gz"
bash "$script_dir/package-sdk.sh" "$prefix" "$archive"

hidden_stage="$work_root/stage-hidden"
mv "$stage_parent" "$hidden_stage"
bash "$script_dir/validate-artifact.sh" "$out_dir" "$linkage" "$architecture" "$architecture"

echo "SDK_ARCHIVE=$archive"
