#!/usr/bin/env bash
set -euo pipefail

cmake_version="4.4.3"
cmake_sha256="0c5d65251c14cc884bfa16bdbed3c263ce5bffe2e21c0d0d00962cb0610464fa"
archive_name="cmake-${cmake_version}-macos-universal.tar.gz"
download_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/${archive_name}"
tools_root="${RUNNER_TEMP:?RUNNER_TEMP is required}/occt-sdk-tools"
archive="$tools_root/$archive_name"
install_root="$tools_root/cmake-$cmake_version"

mkdir -p "$tools_root"
if [[ ! -x "$install_root/CMake.app/Contents/bin/cmake" ]]; then
  rm -rf "$install_root"
  curl --fail --location --retry 3 --output "$archive" "$download_url"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$cmake_sha256" ]]; then
    echo "CMake archive SHA-256 mismatch: $actual" >&2
    exit 1
  fi
  mkdir -p "$install_root"
  tar -xzf "$archive" -C "$install_root" --strip-components=1
fi

cmake_bin="$install_root/CMake.app/Contents/bin/cmake"
actual_version="$("$cmake_bin" --version | sed -n '1s/^cmake version //p')"
if [[ "$actual_version" != "$cmake_version" ]]; then
  echo "expected CMake $cmake_version, found $actual_version" >&2
  exit 1
fi

echo "$(dirname "$cmake_bin")" >> "$GITHUB_PATH"
echo "CMAKE_BIN=$cmake_bin" >> "$GITHUB_ENV"
echo "CMAKE_VERSION=$cmake_version" >> "$GITHUB_ENV"
echo "CMAKE_ARCHIVE_SHA256=$cmake_sha256" >> "$GITHUB_ENV"
