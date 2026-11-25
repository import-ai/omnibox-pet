#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="桌宠小黑"
TMP_BUILD_DIR="$(mktemp -d "$ROOT/.xiaohei-build.XXXXXX")"
trap 'rm -rf "$TMP_BUILD_DIR"' EXIT
APP_BUNDLE="$TMP_BUILD_DIR/${APP_NAME}.app"
OUTPUT_BUNDLE="$ROOT/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Building ${APP_NAME}.app..."
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

cp "$ROOT/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"

SWIFT_SOURCES=(
    "$ROOT/Sources/KeyMap.swift"
    "$ROOT/Sources/InputEngine.swift"
    "$ROOT/Sources/CatPhysics.swift"
    "$ROOT/Sources/CatRenderer.swift"
    "$ROOT/Sources/XiaoheiArt.swift"
    "$ROOT/Sources/XiaoheiRenderer.swift"
    "$ROOT/Sources/OverlayWindow.swift"
    "$ROOT/Sources/AppDelegate.swift"
    "$ROOT/Sources/main.swift"
)

COMMON_FLAGS=(
    -swift-version 5
    -O
    -framework AppKit
    -framework CoreGraphics
    -framework QuartzCore
    -framework IOKit
    -framework ApplicationServices
)

TMP_BIN_DIR="$TMP_BUILD_DIR"

echo "==> Compiling arm64 slice (macOS 11.0+)..."
swiftc "${COMMON_FLAGS[@]}" -target arm64-apple-macos11.0 "${SWIFT_SOURCES[@]}" -o "$TMP_BIN_DIR/${APP_NAME}_arm64"

echo "==> Compiling x86_64 (Intel) slice (macOS 11.0+)..."
swiftc "${COMMON_FLAGS[@]}" -target x86_64-apple-macos11.0 "${SWIFT_SOURCES[@]}" -o "$TMP_BIN_DIR/${APP_NAME}_x86_64"

echo "==> Creating Universal binary (arm64 + x86_64)..."
lipo -create "$TMP_BIN_DIR/${APP_NAME}_arm64" "$TMP_BIN_DIR/${APP_NAME}_x86_64" -output "$MACOS_DIR/$APP_NAME"
lipo -info "$MACOS_DIR/$APP_NAME"

# Keep a consistent signing identity across builds so macOS can match privacy grants.
# Switching identities can require granting Input Monitoring again. Order of preference:
#   1. $XIAOHEI_SIGN_IDENTITY (CI imports the shared certificate and sets this)
#   2. Developer ID Application / Apple Development certificate in the keychain
#   3. Self-signed "KuroCat Code Signing" certificate (create once: scripts/create-macos-signing-cert.sh)
#   4. Ad-hoc (last resort — permission will be lost on every update)
SIGN_IDENTITY="${XIAOHEI_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/{print $2; exit}')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
    # Prefer the long-lived shared "KuroCat Code Signing" cert (matches CI so permissions survive updates)
    if security find-identity -p codesigning 2>/dev/null | grep -q '"KuroCat Code Signing"'; then
        SIGN_IDENTITY="KuroCat Code Signing"
    fi
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:/{print $2; exit}')"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with stable certificate: $SIGN_IDENTITY"
    signing_options=(--options runtime)
    if [ -n "${XIAOHEI_REQUIRE_STABLE_SIGNATURE:-}" ]; then
        signing_options+=(--timestamp)
    fi
    codesign --force --sign "$SIGN_IDENTITY" "${signing_options[@]}" --identifier "pro.omnibox.xiaohei-pet" "$APP_BUNDLE"
else
    echo "==> WARNING: no stable signing certificate found — signing ad-hoc." >&2
    echo "    Users will have to re-enable Input Monitoring after EVERY update." >&2
    echo "    Run scripts/create-macos-signing-cert.sh once to fix this." >&2
    if [ -n "${XIAOHEI_REQUIRE_STABLE_SIGNATURE:-}" ]; then
        echo "[ERROR] XIAOHEI_REQUIRE_STABLE_SIGNATURE is set: refusing to ship an ad-hoc build." >&2
        exit 1
    fi
    codesign --force --deep --sign - --identifier "pro.omnibox.xiaohei-pet" "$APP_BUNDLE"
fi
echo "==> Designated requirement (what macOS uses to recognise KuroCat across updates):"
codesign -d -r- "$APP_BUNDLE" 2>&1 | grep -i designated || true

if [ -e "$OUTPUT_BUNDLE" ]; then
    mv "$OUTPUT_BUNDLE" "$TMP_BUILD_DIR/previous.app"
fi
if ! mv "$APP_BUNDLE" "$OUTPUT_BUNDLE"; then
    if [ -e "$TMP_BUILD_DIR/previous.app" ]; then
        mv "$TMP_BUILD_DIR/previous.app" "$OUTPUT_BUNDLE"
    fi
    exit 1
fi
echo "==> Built successfully: $OUTPUT_BUNDLE"
