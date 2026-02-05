#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/ios"
THIRD_PARTY_DIR="$ROOT_DIR/.build/third_party"
IOS_FRAMEWORKS_DIR="$ROOT_DIR/ios/Frameworks"
NATIVE_IOS_FRAMEWORKS_DIR="$ROOT_DIR/native/ios/Frameworks"

mkdir -p "$BUILD_DIR" "$THIRD_PARTY_DIR" "$IOS_FRAMEWORKS_DIR" "$NATIVE_IOS_FRAMEWORKS_DIR"

# -------------------------
# CONFIG
# -------------------------

ZXING_GIT_URL="https://github.com/zxing-cpp/zxing-cpp.git"
ZXING_GIT_REF="v2.2.1"

OPENCV_ZIP_URL="${OPENCV_ZIP_URL:-}"
OPENCV_ZIP_SHA256="${OPENCV_ZIP_SHA256:-}"

# -------------------------
# Helpers
# -------------------------

log() { echo "[$(date +"%H:%M:%S")] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1"; exit 1; }
}

ensure_tools() {
  need_cmd git
  need_cmd cmake
  need_cmd xcodebuild
  need_cmd lipo
  need_cmd rsync
  need_cmd unzip
}

clone_or_update_repo() {
  local url="$1"
  local ref="$2"
  local dest="$3"

  if [[ ! -d "$dest/.git" ]]; then
    log "Cloning $url -> $dest"
    git clone --branch "$ref" --depth 1 "$url" "$dest"
  else
    log "Updating $dest"
    git -C "$dest" fetch --all --tags
    git -C "$dest" checkout "$ref"
    git -C "$dest" pull --ff-only || true
  fi
}

prepare_zxing_headers_bundle() {
  local zxing_src="$1"
  local out_headers_root="$2"
  local zxing_headers_dir="$out_headers_root/ZXing"

  rm -rf "$out_headers_root"
  mkdir -p "$zxing_headers_dir"

  cp "$zxing_src/core/src/"*.h "$zxing_headers_dir/"

  cat > "$zxing_headers_dir/ZXing.h" <<'EOF'
#pragma once
EOF

  cat > "$zxing_headers_dir/module.modulemap" <<'EOF'
framework module ZXing {
  umbrella header "ZXing.h"
  export *
  module * { export * }
}
EOF
}

build_zxing_one() {
  local zxing_src="$1"
  local build_out="$2"
  local sdk="$3"
  local arch="$4"

  rm -rf "$build_out"
  mkdir -p "$build_out"
  pushd "$build_out" >/dev/null

  log "Configuring ZXing for $sdk $arch"

  cmake "$zxing_src" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DZXING_BUILD_SHARED=OFF \
    -DZXING_BUILD_EXAMPLES=OFF \
    -DZXING_BUILD_TESTS=OFF \
    -DZXING_BUILD_UNIT_TESTS=OFF \
    -DZXING_ENABLE_QRCODE=ON \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_EXTENSIONS=OFF

  cmake --build . --config Release --target ZXing
  popd >/dev/null
}

create_zxing_xcframework() {
  local device_lib="$1"
  local sim_arm64_lib="$2"
  local sim_x64_lib="$3"
  local headers_root="$4"
  local out_xc="$5"

  rm -rf "$out_xc"
  lipo -create "$sim_arm64_lib" "$sim_x64_lib" -output "$BUILD_DIR/libZXing_simulator.a"

  xcodebuild -create-xcframework \
    -library "$device_lib" -headers "$headers_root" \
    -library "$BUILD_DIR/libZXing_simulator.a" -headers "$headers_root" \
    -output "$out_xc"
}

ensure_opencv_present() {
  if [[ -d "$NATIVE_IOS_FRAMEWORKS_DIR/opencv2.framework" ]] || \
     [[ -d "$NATIVE_IOS_FRAMEWORKS_DIR/opencv2.xcframework" ]]; then
    log "OpenCV present"
    return
  fi

  [[ -n "$OPENCV_ZIP_URL" ]] || {
    echo "OpenCV missing and OPENCV_ZIP_URL not set"
    exit 1
  }

  curl -L "$OPENCV_ZIP_URL" -o "$THIRD_PARTY_DIR/opencv_ios.zip"
  unzip -o "$THIRD_PARTY_DIR/opencv_ios.zip" -d "$NATIVE_IOS_FRAMEWORKS_DIR"
}

# 🔑 MAIN CHANGE IS HERE
build_vision_scan_native_xcframework() {
  local zxing_xc="$1"
  local out_xc="$2"

  local project_path="$ROOT_DIR/native/ios/vision_scan_native/vision_scan_native.xcodeproj"
  local scheme="vision_scan_native"
  local derived="$BUILD_DIR/derived"

  rm -rf "$derived"
  mkdir -p "$derived"

  ensure_opencv_present

  rm -rf "$NATIVE_IOS_FRAMEWORKS_DIR/ZXing.xcframework"
  rsync -a "$zxing_xc/" "$NATIVE_IOS_FRAMEWORKS_DIR/ZXing.xcframework/"

  log "Archiving vision_scan_native (iphoneos)"
  xcodebuild archive \
    -project "$project_path" \
    -scheme "$scheme" \
    -configuration Release \
    -sdk iphoneos \
    -archivePath "$derived/vision_scan_native-iphoneos.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO

  rm -rf "$out_xc"
  xcodebuild -create-xcframework \
    -framework "$derived/vision_scan_native-iphoneos.xcarchive/Products/Library/Frameworks/vision_scan_native.framework" \
    -output "$out_xc"
}

# -------------------------
# Main
# -------------------------

main() {
  ensure_tools

  local zxing_src="$THIRD_PARTY_DIR/zxing-cpp"
  clone_or_update_repo "$ZXING_GIT_URL" "$ZXING_GIT_REF" "$zxing_src"
  git -C "$zxing_src" submodule update --init --recursive

  local b_device="$BUILD_DIR/zxing-ios-arm64"
  local b_sim_arm64="$BUILD_DIR/zxing-sim-arm64"
  local b_sim_x64="$BUILD_DIR/zxing-sim-x86_64"

  build_zxing_one "$zxing_src" "$b_device" "iphoneos" "arm64"
  build_zxing_one "$zxing_src" "$b_sim_arm64" "iphonesimulator" "arm64"
  build_zxing_one "$zxing_src" "$b_sim_x64" "iphonesimulator" "x86_64"

  local headers_root="$BUILD_DIR/zxing_headers"
  prepare_zxing_headers_bundle "$zxing_src" "$headers_root"

  local zxing_xc="$BUILD_DIR/ZXing.xcframework"
  create_zxing_xcframework \
    "$b_device/core/libZXing.a" \
    "$b_sim_arm64/core/libZXing.a" \
    "$b_sim_x64/core/libZXing.a" \
    "$headers_root" \
    "$zxing_xc"

  local out_native_xc="$IOS_FRAMEWORKS_DIR/vision_scan_native.xcframework"
  build_vision_scan_native_xcframework "$zxing_xc" "$out_native_xc"

  log "✅ vision_scan_native.xcframework ready:"
  log "   $out_native_xc"
}

main "$@"