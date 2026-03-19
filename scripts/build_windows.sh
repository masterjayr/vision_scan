#!/usr/bin/env bash
set -eu

# -------------------------------------------------
# Paths
# -------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_WINDOWS="$ROOT_DIR/native/windows"
BUILD_DIR="$NATIVE_WINDOWS/build"
# Example app runner dirs (so "flutter run -d windows" finds the DLL)
EXAMPLE_RUNNER_DEBUG="$ROOT_DIR/example/build/windows/x64/runner/Debug"
EXAMPLE_RUNNER_RELEASE="$ROOT_DIR/example/build/windows/x64/runner/Release"

# -------------------------------------------------
# Config
# -------------------------------------------------
CMAKE_CONFIG="${CMAKE_CONFIG:-Release}"
# Use Windows CMake with VS generator (Android SDK cmake does not have it).
CMAKE_EXE="${CMAKE_EXE:-cmake}"

# Dependency zips (GitHub Releases direct .zip URLs).
# If these aren't provided, the script will assume native/windows/libs already exists.
#
# Default OpenCV+ZXing artifact (single zip that contains both `opencv/` and `zxing/` folders):
#   https://github.com/masterjayr/scanner-binaries/releases/download/opencv-windowsv1.0.0/opencv-windows.zip
OPENCV_ZIP_URL="${OPENCV_ZIP_URL:-https://github.com/masterjayr/scanner-binaries/releases/download/opencv-windowsv1.0.0/opencv-windows.zip}"
ZXING_ZIP_URL="${ZXING_ZIP_URL:-}"

# Where to download zips locally before extracting.
THIRD_PARTY_DIR="$ROOT_DIR/.build/third_party/windows"
# On Windows, if default "cmake" lacks VS generator, try standard install paths
# (Git Bash: /c/..., WSL: /mnt/c/...)
if [[ "$CMAKE_EXE" == cmake ]]; then
  for candidate in "/c/Program Files/cmake/bin/cmake.exe" "/c/Program Files/CMake/bin/cmake.exe" "/mnt/c/Program Files/cmake/bin/cmake.exe" "/mnt/c/Program Files/CMake/bin/cmake.exe"; do
    if [[ -f "$candidate" ]] && [[ -x "$candidate" ]]; then
      CMAKE_EXE="$candidate"
      break
    fi
  done
fi

# -------------------------------------------------
# Helpers
# -------------------------------------------------
log() { echo "[$(date +"%H:%M:%S")] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Missing required tool: $1"
    exit 1
  }
}

ensure_tools() {
  if [[ "$CMAKE_EXE" == cmake ]]; then
    need_cmd cmake
  elif [[ ! -f "$CMAKE_EXE" ]]; then
    echo "❌ CMake not found: $CMAKE_EXE"
    echo "   Set CMAKE_EXE to Windows CMake, e.g. CMAKE_EXE=\"C:/Program Files/CMake/bin/cmake.exe\""
    exit 1
  fi
  if ! "$CMAKE_EXE" --help 2>/dev/null | grep -q "Visual Studio 17 2022"; then
    echo "❌ This CMake does not support generator 'Visual Studio 17 2022'."
    echo "   Your PATH may point to Android SDK cmake. Use Windows CMake instead:"
    echo "   CMAKE_EXE=\"C:/Program Files/CMake/bin/cmake.exe\" bash scripts/build_windows.sh"
    echo "   Or run from 'x64 Native Tools Command Prompt for VS 2022'."
    exit 1
  fi
}

# -------------------------------------------------
# Download + extract dependency zips
# -------------------------------------------------
download_zip() {
  local url="$1"
  local out_zip="$2"

  log "Downloading: $url"
  need_cmd curl

  mkdir -p "$THIRD_PARTY_DIR"
  curl -L --fail -o "$out_zip" "$url"
}

extract_zip_into_libs() {
  local zip_path="$1"
  local libs_root="$NATIVE_WINDOWS/libs"

  need_cmd unzip

  mkdir -p "$libs_root"
  log "Unzipping: $zip_path -> $libs_root"
  unzip -o -q "$zip_path" -d "$libs_root"
}

ensure_deps() {
  local opencv_dir="$NATIVE_WINDOWS/libs/opencv"
  local zxing_dir="$NATIVE_WINDOWS/libs/zxing"

  if [[ ! -d "$opencv_dir" ]]; then
    if [[ -z "$OPENCV_ZIP_URL" ]]; then
      echo "❌ OpenCV deps missing ($opencv_dir) and OPENCV_ZIP_URL is not set."
      echo "   Provide a direct zip URL via OPENCV_ZIP_URL."
      exit 1
    fi
    local opencv_zip="$THIRD_PARTY_DIR/opencv.zip"
    download_zip "$OPENCV_ZIP_URL" "$opencv_zip"
    extract_zip_into_libs "$opencv_zip"
  fi

  if [[ ! -d "$zxing_dir" ]]; then
    if [[ -z "$ZXING_ZIP_URL" ]]; then
      echo "❌ ZXing deps missing ($zxing_dir) and ZXING_ZIP_URL is not set."
      echo "   Provide a direct zip URL via ZXING_ZIP_URL."
      exit 1
    fi
    local zxing_zip="$THIRD_PARTY_DIR/zxing.zip"
    download_zip "$ZXING_ZIP_URL" "$zxing_zip"
    extract_zip_into_libs "$zxing_zip"
  fi
}

# -------------------------------------------------
# Build vision_scan_native.dll
# -------------------------------------------------
build_native_dll() {
  local src_dir="$NATIVE_WINDOWS" build_dir="$BUILD_DIR"
  if command -v wslpath &>/dev/null; then
    src_dir=$(wslpath -w "$NATIVE_WINDOWS")
    build_dir=$(wslpath -w "$BUILD_DIR")
  fi
  log "Configuring Windows native (CMake)"
  "$CMAKE_EXE" -S "$src_dir" -B "$build_dir" -G "Visual Studio 17 2022" -A x64

  log "Building vision_scan_native ($CMAKE_CONFIG)"
  "$CMAKE_EXE" --build "$build_dir" --config "$CMAKE_CONFIG"

  local dll_src="$BUILD_DIR/$CMAKE_CONFIG/vision_scan_native.dll"
  if [[ ! -f "$dll_src" ]]; then
    echo "❌ DLL not found: $dll_src"
    exit 1
  fi
  log "✅ Built: $dll_src"
}

# -------------------------------------------------
# Copy DLL into example app for development
# -------------------------------------------------
copy_to_example() {
  local dll_src="$BUILD_DIR/$CMAKE_CONFIG/vision_scan_native.dll"

  for dir in "$EXAMPLE_RUNNER_DEBUG" "$EXAMPLE_RUNNER_RELEASE"; do
    mkdir -p "$dir"
    cp "$dll_src" "$dir/"
    log "📦 Copied vision_scan_native.dll -> $dir"
  done

  # Optional: copy OpenCV runtime DLL if present (so example runs without PATH)
  local opencv_bin="$NATIVE_WINDOWS/libs/opencv/bin"
  local opencv_lib="$NATIVE_WINDOWS/libs/opencv/lib"
  for opencv_dll in "$opencv_bin"/opencv_world*.dll "$opencv_lib"/opencv_world*.dll; do
    if [[ -f "$opencv_dll" ]]; then
      for dir in "$EXAMPLE_RUNNER_DEBUG" "$EXAMPLE_RUNNER_RELEASE"; do
        cp "$opencv_dll" "$dir/"
        log "📦 Copied $(basename "$opencv_dll") -> $dir"
      done
      break
    fi
  done
}

# -------------------------------------------------
# Main
# -------------------------------------------------
main() {
  ensure_tools

  ensure_deps

  # Basic sanity checks so failures are obvious.
  if [[ ! -d "$NATIVE_WINDOWS/libs/opencv/include/opencv2" ]] || [[ ! -d "$NATIVE_WINDOWS/libs/opencv/lib" ]]; then
    echo "❌ OpenCV extracted but missing expected paths."
    echo "   Expected: native/windows/libs/opencv/include/opencv2 and native/windows/libs/opencv/lib"
    exit 1
  fi
  if [[ ! -d "$NATIVE_WINDOWS/libs/zxing/include" ]] || [[ ! -d "$NATIVE_WINDOWS/libs/zxing/lib" ]]; then
    echo "❌ ZXing extracted but missing expected paths."
    echo "   Expected: native/windows/libs/zxing/include and native/windows/libs/zxing/lib"
    exit 1
  fi

  build_native_dll
  copy_to_example

  log "✅ Vision Scan Windows build complete"
  log "   Run the example: cd example && flutter run -d windows"
}

main "$@"
