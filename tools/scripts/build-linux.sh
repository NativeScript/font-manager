#!/bin/bash
# Builds libfontmanager.so (packages/font-manager/src-native/linux) into
# packages/font-manager/platforms/linux.
#
# fontconfig is linked by its soname (libfontconfig.so.1), so no development packages or sysroot
# are needed, only Rust. Pango is looked up at run time.
#
# Usage: tools/scripts/build-linux.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/../.."

PROFILE=release
[ "${1:-}" = "--debug" ] && PROFILE=debug

case "$(uname -m)" in
    x86_64) ARCH=x64 ;;
    aarch64) ARCH=arm64 ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

CRATE=packages/font-manager/src-native/linux
FLAGS=()
[ "$PROFILE" = release ] && FLAGS+=(--release)
cargo build --manifest-path "$CRATE/Cargo.toml" "${FLAGS[@]}"

OUT=packages/font-manager/platforms/linux
mkdir -p "$OUT/lib/$ARCH" "$OUT/include"
install -m 755 "$CRATE/target/$PROFILE/libfontmanager.so" "$OUT/lib/$ARCH/libfontmanager.so"
cp "$CRATE/include/font_manager.h" "$OUT/include/"
echo "built $OUT/lib/$ARCH/libfontmanager.so ($PROFILE)"
