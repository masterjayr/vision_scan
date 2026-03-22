#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Paths
# -------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/android"
THIRD_PARTY_DIR="$ROOT_DIR/.build/third_party"
OUT_ANDROID_DIR="$ROOT_DIR/native/android"

mkdir -p "$BUILD_DIR" "$THIRD_PARTY_DIR" "$OUT_ANDROID_DIR"

# -------------------------------------------------
# Config
# -------------------------------------------------
ZXING_GIT_URL="https://github.com/zxing-cpp/zxing-cpp.git"
ZXING_GIT_REF="v2.2.1"

ANDROID_API=21
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

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
  need_cmd git
  need_cmd cmake
  need_cmd unzip
  need_cmd file
  need_cmd curl
}

# Resolves ANDROID_NDK_HOME to a path that contains build/cmake/android.toolchain.cmake.
# On macOS the NDK lives under the SDK, e.g. ~/Library/Android/sdk/ndk/<version>.
# If ANDROID_NDK_HOME is wrong (e.g. /ndk/...), fall back to ANDROID_HOME / ANDROID_SDK_ROOT.
resolve_android_ndk_home() {
  local toolchain
  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    toolchain="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
    if [[ -f "$toolchain" ]]; then
      echo "$ANDROID_NDK_HOME"
      return 0
    fi
    echo "⚠️  ANDROID_NDK_HOME is set but invalid: ${ANDROID_NDK_HOME}" >&2
    echo "    (missing: $toolchain)" >&2
  fi

  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk" || ! -d "$sdk/ndk" ]]; then
    echo "❌ Could not find the Android NDK." >&2
    echo "   Install the NDK via Android Studio SDK Manager, then either:" >&2
    echo "   • export ANDROID_HOME=\"\$HOME/Library/Android/sdk\"   # typical on macOS" >&2
    echo "   • export ANDROID_NDK_HOME=\"\$ANDROID_HOME/ndk/<version>\"" >&2
    exit 1
  fi

  local -a candidates=()
  local d
  for d in "$sdk"/ndk/*; do
    [[ -d "$d" && -f "$d/build/cmake/android.toolchain.cmake" ]] && candidates+=("$d")
  done
  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "❌ No usable NDK under $sdk/ndk (need build/cmake/android.toolchain.cmake)." >&2
    exit 1
  fi

  printf '%s\n' "${candidates[@]}" | sort -V | tail -1
}

clone_or_update_repo() {
  local url="$1"
  local ref="$2"
  local dest="$3"

  if [[ ! -d "$dest/.git" ]]; then
    log "Cloning ZXing into $dest"
    git clone "$url" "$dest"
    git -C "$dest" checkout "$ref"
    log "Initializing ZXing submodules"
    git -C "$dest" submodule update --init --recursive
  else
    log "Updating ZXing"
    git -C "$dest" fetch --all --tags
    git -C "$dest" checkout "$ref"
    if git -C "$dest" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      git -C "$dest" pull --ff-only
    fi
    git -C "$dest" submodule update --init --recursive
  fi
}

# -------------------------------------------------
# OpenCV (Android)
# -------------------------------------------------
ensure_opencv_android() {
  local sdk_dir="$THIRD_PARTY_DIR/opencv-android-sdk"

  if [[ -d "$sdk_dir" ]]; then
    log "OpenCV Android SDK already present"
    return
  fi

  log "Downloading OpenCV Android SDK"
  local zip="$THIRD_PARTY_DIR/opencv_android.zip"

  curl -L \
    "https://github.com/masterjayr/scanner-binaries/releases/download/opencv-android-v1.0.0/OpenCV-android-sdk.zip" \
    -o "$zip"

  unzip -q "$zip" -d "$THIRD_PARTY_DIR"
  mv "$THIRD_PARTY_DIR"/OpenCV-android-sdk "$sdk_dir"
}

# -------------------------------------------------
# Build ZXing for one ABI
# -------------------------------------------------
build_zxing_one() {
  local zxing_src="$1"
  local abi="$2"
  local out_dir="$3"

  local build_dir="$BUILD_DIR/zxing-$abi"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  log "Configuring ZXing for ABI=$abi"

  cmake -S "$zxing_src" -B "$build_dir" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DZXING_BUILD_SHARED=OFF \
    -DZXING_BUILD_EXAMPLES=OFF \
    -DZXING_BUILD_TESTS=OFF \
    -DZXING_BUILD_UNIT_TESTS=OFF \
    -DCMAKE_SYSTEM_NAME=Android \
    -DANDROID_ABI="$abi" \
    -DCMAKE_ANDROID_ARCH_ABI="$abi" \
    -DANDROID_NDK="$ANDROID_NDK_HOME" \
    -DCMAKE_ANDROID_NDK="$ANDROID_NDK_HOME" \
    -DANDROID_PLATFORM="android-$ANDROID_API" \
    -DCMAKE_ANDROID_PLATFORM="android-$ANDROID_API" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DCMAKE_CXX_STANDARD=20 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON

  log "Building ZXing for ABI=$abi"
  cmake --build "$build_dir" --target ZXing --config Release

  local lib="$build_dir/core/libZXing.a"
  [[ -f "$lib" ]] || { echo "❌ libZXing.a not found for ABI=$abi"; exit 1; }

  mkdir -p "$out_dir/$abi"
  cp "$lib" "$out_dir/$abi/libZXing.a"
}

# -------------------------------------------------
# Runtime libs (OpenCV + libc++)
# -------------------------------------------------
abi_to_triple() {
  case "$1" in
    arm64-v8a) echo "aarch64-linux-android" ;;
    armeabi-v7a) echo "arm-linux-androideabi" ;;
    x86_64) echo "x86_64-linux-android" ;;
    *) echo "❌ Unknown ABI: $1"; exit 1 ;;
  esac
}

ndk_host_tag() {
  local prebuilt="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"

  for host in darwin-x86_64 darwin-arm64 linux-x86_64 windows-x86_64; do
    if [[ -d "$prebuilt/$host" ]]; then
      echo "$host"
      return
    fi
  done

  echo "❌ Could not determine NDK host tag"
  exit 1
}

copy_android_runtime_libs() {
  local abi="$1"
  local triple
  triple="$(abi_to_triple "$abi")"
  local host
  host="$(ndk_host_tag)"

  local opencv_libs="$THIRD_PARTY_DIR/opencv-android-sdk/sdk/native/jni/libs"
  local libcxx="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/$triple/libc++_shared.so"

  mkdir -p "$OUT_ANDROID_DIR/$abi"

  log "Copying OpenCV runtime for $abi"
  cp "$opencv_libs/$abi/libopencv_java4.so" "$OUT_ANDROID_DIR/$abi/"

  log "Copying libc++_shared for $abi"
  [[ -f "$libcxx" ]] || {
    echo "❌ libc++_shared.so not found: $libcxx"
    exit 1
  }

  cp "$libcxx" "$OUT_ANDROID_DIR/$abi/libc++_shared.so"
}

# -------------------------------------------------
# Build vision_scan_native.so
# -------------------------------------------------
assert_so_matches_abi() {
  local abi="$1"
  local so="$2"
  local info
  info="$(file "$so")"

  case "$abi" in
    arm64-v8a) echo "$info" | grep -qi "ELF 64-bit.*aarch64" ;;
    armeabi-v7a) echo "$info" | grep -qi "ELF 32-bit.*ARM" ;;
    x86_64) echo "$info" | grep -qi "ELF 64-bit.*x86-64" ;;
  esac || {
    echo "❌ ABI mismatch: $info"
    exit 1
  }
}

build_plugin_so_one() {
  local abi="$1"
  local build_dir="$BUILD_DIR/plugin-$abi"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  log "Building libvision_scan_native.so for $abi"

  cmake -S "$ROOT_DIR/native/android" -B "$build_dir" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Android \
    -DANDROID_ABI="$abi" \
    -DCMAKE_ANDROID_NDK="$ANDROID_NDK_HOME" \
    -DANDROID_PLATFORM="android-$ANDROID_API" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"

  cmake --build "$build_dir" --target vision_scan_native --config Release

  local so="$build_dir/libvision_scan_native.so"
  [[ -f "$so" ]] || { echo "❌ .so not found"; exit 1; }

  assert_so_matches_abi "$abi" "$so"
}

copy_plugin_outputs_one() {
  local abi="$1"
  local build_dir="$BUILD_DIR/plugin-$abi"
  local so="$build_dir/libvision_scan_native.so"

  local plugin_jni="$ROOT_DIR/android/src/main/jniLibs/$abi"
  mkdir -p "$plugin_jni"
  cp "$so" "$plugin_jni/"

  log "✅ Copied outputs for $abi"
}

# -------------------------------------------------
# Headers
# -------------------------------------------------
copy_opencv_headers() {
  local src="$THIRD_PARTY_DIR/opencv-android-sdk/sdk/native/jni/include/opencv2"
  local dst="$ROOT_DIR/native/include/opencv2"

  [[ -d "$dst" ]] || cp -R "$src" "$dst"
}

copy_zxing_headers() {
  local src="$THIRD_PARTY_DIR/zxing-cpp/core/src"
  local dst="$ROOT_DIR/native/include/ZXing"

  [[ -d "$dst" ]] || {
    mkdir -p "$dst"
    cp "$src"/*.h "$dst/"
  }
}

copy_example_outputs_one() {
  local abi="$1"

  local example_jni="$ROOT_DIR/example/android/app/src/main/jniLibs/$abi"
  mkdir -p "$example_jni"

  # Plugin .so
  cp "$BUILD_DIR/plugin-$abi/libvision_scan_native.so" "$example_jni/"

  # Runtime deps
  cp "$OUT_ANDROID_DIR/$abi/libopencv_java4.so" "$example_jni/"
  cp "$OUT_ANDROID_DIR/$abi/libc++_shared.so" "$example_jni/"

  log "📦 Copied example JNI outputs for $abi"
}

# -------------------------------------------------
# Main
# -------------------------------------------------
main() {
  ensure_tools
  ANDROID_NDK_HOME="$(resolve_android_ndk_home)"
  export ANDROID_NDK_HOME
  log "Using ANDROID_NDK_HOME=$ANDROID_NDK_HOME"

  ensure_opencv_android
  copy_opencv_headers

  local zxing_src="$THIRD_PARTY_DIR/zxing-cpp"
  clone_or_update_repo "$ZXING_GIT_URL" "$ZXING_GIT_REF" "$zxing_src"
  copy_zxing_headers

  for abi in "${ABIS[@]}"; do
    build_zxing_one "$zxing_src" "$abi" "$OUT_ANDROID_DIR"
    copy_android_runtime_libs "$abi"
    build_plugin_so_one "$abi"
    copy_plugin_outputs_one "$abi"
    copy_example_outputs_one "$abi"
  done

  log "✅ Vision Scan Android build complete"
}

main "$@"