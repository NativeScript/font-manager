#!/usr/bin/env bash
set -euo pipefail

# Usage: tools/scripts/build-xcframework.sh [output-dir]
#
# SPM packages archive to a relocatable object file, not a framework, so
# each slice is linked into a static library and packaged with the public
# headers and a module map.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/packages/font-manager/src-native/ios/FontManager"
SCHEME="FontManager"
OUT_DIR="${1:-$REPO_ROOT/dist/spm}"
WORK_DIR="$OUT_DIR/build"

PLATFORMS=("iOS" "iOS Simulator" "visionOS" "visionOS Simulator")

rm -rf "$OUT_DIR"
mkdir -p "$WORK_DIR"

# publicHeadersPath is "." in the package, so every header is public; an
# umbrella directory mirrors the module map SPM generates for source builds.
HEADERS_DIR="$WORK_DIR/Headers"
mkdir -p "$HEADERS_DIR"
cp "$PACKAGE_DIR/Sources/FontManager/"*.h "$HEADERS_DIR/"
cat > "$HEADERS_DIR/module.modulemap" <<'EOF'
module FontManager {
    umbrella "."
    export *
    module * { export * }
}
EOF

XCFRAMEWORK_ARGS=()
for PLATFORM in "${PLATFORMS[@]}"; do
  SLUG="$(echo "$PLATFORM" | tr '[:upper:] ' '[:lower:]-')"
  ARCHIVE="$WORK_DIR/$SLUG.xcarchive"

  echo "▸ Archiving $SCHEME for $PLATFORM"
  (cd "$PACKAGE_DIR" && xcodebuild archive \
    -scheme "$SCHEME" \
    -destination "generic/platform=$PLATFORM" \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    -quiet \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO)

  OBJECT="$(find "$ARCHIVE/Products" -name "$SCHEME.o" -type f | head -1)"
  if [ -z "$OBJECT" ]; then
    echo "error: no $SCHEME.o found in $ARCHIVE" >&2
    exit 1
  fi

  mkdir -p "$WORK_DIR/$SLUG"
  libtool -static -o "$WORK_DIR/$SLUG/lib$SCHEME.a" "$OBJECT"
  XCFRAMEWORK_ARGS+=(-library "$WORK_DIR/$SLUG/lib$SCHEME.a" -headers "$HEADERS_DIR")
done

xcodebuild -create-xcframework "${XCFRAMEWORK_ARGS[@]}" -output "$OUT_DIR/$SCHEME.xcframework"

ditto -c -k --sequesterRsrc --keepParent "$OUT_DIR/$SCHEME.xcframework" "$OUT_DIR/$SCHEME.xcframework.zip"

CHECKSUM="$(cd "$REPO_ROOT" && swift package compute-checksum "$OUT_DIR/$SCHEME.xcframework.zip")"
echo "$CHECKSUM" > "$OUT_DIR/$SCHEME.xcframework.zip.checksum"
echo "checksum: $CHECKSUM"
