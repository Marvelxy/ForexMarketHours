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
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Embedding Sparkle.framework (auto-updates)"
SPARKLE_FW=""
# Per-arch scratch paths first (custom --scratch-path builds cache artifacts there),
# then the default .build location (plain `swift run` / `swift build`).
SEARCH_DIRS=()
for ARCH in "${ARCHS[@]}"; do
    SEARCH_DIRS+=("$ROOT_DIR/.build-universal/$ARCH/artifacts")
done
SEARCH_DIRS+=("$ROOT_DIR/.build/artifacts")
for DIR in "${SEARCH_DIRS[@]}"; do
    CANDIDATE="$(find "$DIR" -maxdepth 5 -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -type d 2>/dev/null | head -n 1 || true)"
    if [[ -n "$CANDIDATE" && -d "$CANDIDATE" ]]; then
        SPARKLE_FW="$CANDIDATE"
        break
    fi
done
if [[ -z "$SPARKLE_FW" ]]; then
    echo "error: Sparkle.framework not found under ${SEARCH_DIRS[*]}" >&2
    echo "       run 'swift package resolve' / a full 'swift build' first so SPM fetches the Sparkle artifact." >&2
    exit 1
fi
echo "    -> $SPARKLE_FW"
# -R preserves Sparkle's symlinks (Versions/Current) and XPC services.
cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

echo "==> Wiring @rpath for embedded frameworks"
APP_BIN="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if ! otool -l "$APP_BIN" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BIN"
fi

echo "==> Signing (ad-hoc)"
# Inner first so the nested XPC services / Updater.app carry a signature,
# then the outer bundle. (Ad-hoc is fine for local dev; production Sparkle
# updates REQUIRE a Developer ID signature + notarization.)
codesign --force --sign - --timestamp=none "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --deep --timestamp=none "$APP_BUNDLE"

echo "==> Verifying"
codesign --verify --deep --strict "$APP_BUNDLE" && echo "    signature OK"
echo "    architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"

echo "==> Done: $APP_BUNDLE"
