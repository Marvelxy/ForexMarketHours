#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ONLY_ARCH="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ForexMarketHours"
if [[ -n "$ONLY_ARCH" ]]; then
    ARCHS=("$ONLY_ARCH")
else
    ARCHS=(arm64 x86_64)
fi

UNIVERSAL_DIR="$ROOT_DIR/.build-universal/universal"
UNIVERSAL_BIN="$UNIVERSAL_DIR/$APP_NAME"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

cd "$ROOT_DIR"

echo "==> Compiling per-architecture slices ($CONFIGURATION)"
THIN_BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    echo "    -> $ARCH"
    SCRATCH="$ROOT_DIR/.build-universal/$ARCH"
    swift build \
        --configuration "$CONFIGURATION" \
        --arch "$ARCH" \
        --scratch-path "$SCRATCH"

    BINARY="$SCRATCH/$CONFIGURATION/$APP_NAME"
    if [[ ! -f "$BINARY" ]]; then
        echo "error: expected executable at $BINARY" >&2
        exit 1
    fi
    THIN_BINARIES+=("$BINARY")
done

mkdir -p "$UNIVERSAL_DIR"
if [[ "${#THIN_BINARIES[@]}" -eq 1 ]]; then
    echo "==> Single-arch build (${ARCHS[0]}), skipping lipo"
    cp "${THIN_BINARIES[0]}" "$UNIVERSAL_BIN"
else
    echo "==> Merging slices with lipo"
    lipo -create "${THIN_BINARIES[@]}" -output "$UNIVERSAL_BIN"
fi
chmod +x "$UNIVERSAL_BIN"

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"

echo "==> Verifying"
codesign --verify --deep --strict "$APP_BUNDLE" && echo "    signature OK"
echo "    architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"

echo "==> Done: $APP_BUNDLE"
