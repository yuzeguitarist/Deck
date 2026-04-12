#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# DeckClip CLI 构建脚本
#
# 编译 deckclip Rust CLI 二进制（release + strip），
# 可选地将产物注入到 Deck.app 的 Resources 目录中。
#
# 用法:
#   ./build-release.sh                          # 仅编译
#   ./build-release.sh /path/to/Deck.app        # 编译 + 注入到 .app
#
# 环境变量:
#   CARGO      cargo 路径 (默认: cargo)
#   RUSTUP     rustup 路径 (默认: rustup)
#   TARGET     编译目标，支持 native / aarch64-apple-darwin /
#              x86_64-apple-darwin / universal-apple-darwin
#              (默认: 当前架构)
#   KEEP_SLICE_ARTIFACTS=1
#              universal 构建完成后保留两个架构的中间 release 产物
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure cargo is available (rustup installs to ~/.cargo/bin)
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

CARGO="${CARGO:-cargo}"
RUSTUP="${RUSTUP:-rustup}"
KEEP_SLICE_ARTIFACTS="${KEEP_SLICE_ARTIFACTS:-0}"
BINARY_NAME="deckclip"

detect_native_target() {
    local arch=""

    arch="$(uname -m)"
    case "$arch" in
        arm64) echo "aarch64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin" ;;
        *)
            echo "ERROR: unsupported arch: $arch" >&2
            exit 1
            ;;
    esac
}

ensure_target_installed() {
    local target="$1"

    if ! command -v "$RUSTUP" >/dev/null 2>&1; then
        return 0
    fi

    if "$RUSTUP" target list --installed | grep -qx "$target"; then
        return 0
    fi

    echo "   - 安装 Rust target: $target"
    "$RUSTUP" target add "$target"
}

if [[ -z "${TARGET:-}" || "$TARGET" == "native" || "$TARGET" == "current" ]]; then
    TARGET="$(detect_native_target)"
fi

UNIVERSAL_BUILD=0
TARGET_LABEL="$TARGET"
declare -a BUILD_TARGETS=()

case "$TARGET" in
    universal|universal2|universal-apple-darwin)
        UNIVERSAL_BUILD=1
        TARGET_LABEL="universal-apple-darwin"
        BUILD_TARGETS=("aarch64-apple-darwin" "x86_64-apple-darwin")
        ;;
    *)
        BUILD_TARGETS=("$TARGET")
        ;;
esac

echo "=== DeckClip Build ==="
echo "Project: $PROJECT_DIR"
echo "Target:  $TARGET_LABEL"
echo ""

cd "$PROJECT_DIR"
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    declare -a BUILT_BINARIES=()
    STEP=1

    for BUILD_TARGET in "${BUILD_TARGETS[@]}"; do
        ensure_target_installed "$BUILD_TARGET"
        echo "$STEP) cargo build --release --target $BUILD_TARGET ..."
        "$CARGO" build --release --target "$BUILD_TARGET"

        SLICE_BINARY="$PROJECT_DIR/target/$BUILD_TARGET/release/$BINARY_NAME"
        if [[ ! -f "$SLICE_BINARY" ]]; then
            echo "ERROR: binary not found at $SLICE_BINARY"
            exit 1
        fi

        BUILT_BINARIES+=("$SLICE_BINARY")
        STEP=$((STEP + 1))
    done

    OUTPUT_DIR="$PROJECT_DIR/target/universal/release"
    mkdir -p "$OUTPUT_DIR"
    BINARY="$OUTPUT_DIR/$BINARY_NAME"

    echo "$STEP) lipo -create ..."
    xcrun lipo -create "${BUILT_BINARIES[@]}" -output "$BINARY"
    STEP=$((STEP + 1))
else
    ensure_target_installed "$TARGET"
    echo "1) cargo build --release --target $TARGET ..."
    "$CARGO" build --release --target "$TARGET"

    BINARY="$PROJECT_DIR/target/$TARGET/release/$BINARY_NAME"
    if [[ ! -f "$BINARY" ]]; then
        echo "ERROR: binary not found at $BINARY"
        exit 1
    fi

    STEP=2
fi

# Strip debug symbols
echo "$STEP) strip ..."
strip "$BINARY"

# Show size
SIZE=$(du -h "$BINARY" | cut -f1)
ARCH_INFO=$(xcrun lipo -info "$BINARY")
echo "   Binary: $BINARY"
echo "   Size:   $SIZE"
echo "   Arch:   $ARCH_INFO"

# Inject into .app if path provided
if [[ -n "${1:-}" ]]; then
    APP_PATH="$1"
    if [[ ! -d "$APP_PATH" ]]; then
        echo "ERROR: App bundle not found: $APP_PATH"
        exit 1
    fi

    RESOURCES_DIR="$APP_PATH/Contents/Resources"
    mkdir -p "$RESOURCES_DIR"
    cp -f "$BINARY" "$RESOURCES_DIR/$BINARY_NAME"
    chmod +x "$RESOURCES_DIR/$BINARY_NAME"
    echo "$((STEP + 1))) Injected into: $RESOURCES_DIR/$BINARY_NAME"
fi

if [[ "$UNIVERSAL_BUILD" == "1" && "$KEEP_SLICE_ARTIFACTS" != "1" ]]; then
    for BUILD_TARGET in "${BUILD_TARGETS[@]}"; do
        rm -rf "$PROJECT_DIR/target/$BUILD_TARGET/release"
    done
    echo "   Cleaned per-arch release artifacts to save disk space"
fi

echo ""
echo "=== Done ==="
