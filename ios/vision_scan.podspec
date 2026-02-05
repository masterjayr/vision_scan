Pod::Spec.new do |s|
  s.name             = 'vision_scan'
  s.version          = '0.0.4'
  s.summary          = 'High-performance on-device scanner using OpenCV and ZXing'
  s.description      = <<-DESC
    vision_scan is a Flutter FFI plugin that provides fast, on-device
    QR and barcode scanning using OpenCV + ZXing, with real-time
    corner detection and image preprocessing.
  DESC

  s.homepage         = 'https://github.com/masterjayr/vision_scan'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'masterjayr' => 'masterjayr97@email.com' }

  # IMPORTANT:
  # We keep :path so this works for BOTH:
  # - local development (path dependency)
  # - published Flutter plugin
  s.source           = { :path => '.' }

  s.ios.deployment_target = '12.0'

  # -------------------------------------------------
  # Download prebuilt xcframework from GitHub Releases
  # (runs even when plugin is used via :path)
  # -------------------------------------------------
  s.prepare_command = <<-CMD
    set -e

    FRAMEWORK_NAME="vision_scan_native.xcframework"
    ZIP_NAME="vision_scan_native-ios.zip"
    ZIP_URL="https://github.com/masterjayr/vision_scan/releases/download/v#{s.version}/#{ZIP_NAME}"

    if [ -d "$FRAMEWORK_NAME" ]; then
      echo "✅ $FRAMEWORK_NAME already exists, skipping download"
      exit 0
    fi

    echo "⬇️  Downloading $ZIP_URL"
    curl -L -o "$ZIP_NAME" "$ZIP_URL"

    echo "📦 Unzipping $ZIP_NAME"
    unzip -o "$ZIP_NAME"

    rm "$ZIP_NAME"

    if [ ! -d "$FRAMEWORK_NAME" ]; then
      echo "❌ Error: $FRAMEWORK_NAME not found after unzip"
      exit 1
    fi

    echo "✅ $FRAMEWORK_NAME ready"
  CMD

  # -------------------------------------------------
  # Prebuilt native binary
  # -------------------------------------------------
  s.vendored_frameworks = 'vision_scan_native.xcframework'

  # -------------------------------------------------
  # System frameworks required by camera + image pipeline
  # -------------------------------------------------
  s.frameworks = [
    'AVFoundation',
    'CoreVideo',
    'CoreMedia',
    'UIKit'
  ]

  # -------------------------------------------------
  # C++ / ABI compatibility
  # -------------------------------------------------
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end