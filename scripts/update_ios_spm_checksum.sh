#!/usr/bin/env bash
# Update ios/vision_scan/Package.swift binaryTarget URL + checksum to match a zip.
#
# Usage:
#   scripts/update_ios_spm_checksum.sh <zip-path> [version]
#
# Examples:
#   scripts/update_ios_spm_checksum.sh dist/ios/vision_scan_native-ios.zip 0.0.8
#   scripts/update_ios_spm_checksum.sh dist/ios/vision_scan_native-ios.zip   # version from tag/env/podspec
#
# With --check: only verify Package.swift matches the zip (exit 1 on mismatch).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SWIFT="$ROOT_DIR/ios/vision_scan/Package.swift"
PODSPEC="$ROOT_DIR/ios/vision_scan.podspec"

MODE="update"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
fi

ZIP_PATH="${1:-}"
VERSION_ARG="${2:-}"

if [[ -z "$ZIP_PATH" ]]; then
  echo "Usage: $0 [--check] <zip-path> [version]"
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "❌ Zip not found: $ZIP_PATH"
  exit 1
fi

if [[ ! -f "$PACKAGE_SWIFT" ]]; then
  echo "❌ Package.swift not found: $PACKAGE_SWIFT"
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Missing required tool: $1"
    exit 1
  }
}

need_cmd swift
need_cmd python3

VERSION="$VERSION_ARG"
if [[ -z "$VERSION" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" == v* ]]; then
    VERSION="${GITHUB_REF_NAME#v}"
  elif [[ -f "$PODSPEC" ]]; then
    VERSION="$(python3 - "$PODSPEC" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"s\.version\s*=\s*'([^']+)'", text)
print(m.group(1) if m else "")
PY
)"
  fi
fi

if [[ -z "$VERSION" ]]; then
  echo "❌ Could not determine version. Pass it explicitly."
  exit 1
fi

CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
URL="https://github.com/masterjayr/vision_scan/releases/download/v${VERSION}/vision_scan_native-ios.zip"

echo "Version:  $VERSION"
echo "Zip:      $ZIP_PATH"
echo "URL:      $URL"
echo "Checksum: $CHECKSUM"

CURRENT_URL="$(python3 - "$PACKAGE_SWIFT" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'url:\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
CURRENT_CHECKSUM="$(python3 - "$PACKAGE_SWIFT" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'checksum:\s*"([0-9a-f]+)"', text)
print(m.group(1) if m else "")
PY
)"

if [[ "$MODE" == "check" ]]; then
  OK=1
  if [[ "$CURRENT_URL" != "$URL" ]]; then
    echo "❌ Package.swift URL mismatch"
    echo "   expected: $URL"
    echo "   actual:   $CURRENT_URL"
    OK=0
  fi
  if [[ "$CURRENT_CHECKSUM" != "$CHECKSUM" ]]; then
    echo "❌ Package.swift checksum mismatch"
    echo "   expected: $CHECKSUM"
    echo "   actual:   $CURRENT_CHECKSUM"
    OK=0
  fi
  if [[ "$OK" -eq 1 ]]; then
    echo "✅ Package.swift URL and checksum match the zip"
    exit 0
  fi
  exit 1
fi

python3 - "$PACKAGE_SWIFT" "$URL" "$CHECKSUM" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
url = sys.argv[2]
checksum = sys.argv[3]
text = path.read_text()

# Use \g<1> so a checksum starting with hex digits (e.g. 0a...) is not
# parsed as group reference \10, \11, etc.
text2, n_url = re.subn(
    r'(url:\s*")[^"]+(")',
    rf'\g<1>{url}\g<2>',
    text,
    count=1,
)
text3, n_sum = re.subn(
    r'(checksum:\s*")[0-9a-f]+(")',
    rf'\g<1>{checksum}\g<2>',
    text2,
    count=1,
)

if n_url != 1 or n_sum != 1:
    raise SystemExit(f"Failed to patch Package.swift (url={n_url}, checksum={n_sum})")

path.write_text(text3)
print(f"✅ Updated {path}")
PY
