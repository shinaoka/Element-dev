#!/bin/bash
# Build Element Desktop DMG with local seshat and element-web monorepo
# Usage: ./build-local-dmg.sh [--no-clean] [--arm64|--x64|--universal]
#
# Requires: Node.js v24 (v25+ has ESM/CJS compatibility issues with dependencies)
#   nodebrew install v24.14.0 && nodebrew use v24.14.0
#   export PATH="$HOME/.nodebrew/current/bin:$PATH"

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEAN=true  # Default to clean build
ARCH="--arm64"  # Default to arm64

# Monorepo paths
ELEMENT_WEB_ROOT="$SCRIPT_DIR/element-web"
DESKTOP_DIR="$ELEMENT_WEB_ROOT/apps/desktop"
WEB_DIR="$ELEMENT_WEB_ROOT/apps/web"

ensure_icns_icon() {
    local build_dir="$1"
    local icon_png="$build_dir/icon.png"
    local icon_icns="$build_dir/icon.icns"
    local temp_dir
    local iconset_dir

    if [ -f "$icon_icns" ]; then
        echo "$icon_icns"
        return 0
    fi

    if [ ! -f "$icon_png" ]; then
        echo "ERROR: Missing macOS icon source: $icon_png" >&2
        return 1
    fi

    temp_dir="$(mktemp -d)"
    iconset_dir="$temp_dir/icon.iconset"
    mkdir -p "$iconset_dir"

    sips -z 16 16 "$icon_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
    sips -z 32 32 "$icon_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$icon_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
    sips -z 64 64 "$icon_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$icon_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
    sips -z 256 256 "$icon_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$icon_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
    sips -z 512 512 "$icon_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$icon_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$icon_png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$iconset_dir" -o "$icon_icns"
    rm -rf "$temp_dir"
    echo "$icon_icns"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --no-clean)
            CLEAN=false
            ;;
        --arm64|--x64|--universal)
            ARCH="$arg"
            ;;
    esac
done

echo "========================================"
echo "Building Element Desktop DMG (monorepo)"
echo "Architecture: $ARCH"
echo "Clean build: $CLEAN"
echo "========================================"

# 0. Clean build artifacts if requested
if [ "$CLEAN" = true ]; then
    echo ""
    echo "[0/6] Cleaning build artifacts..."

    # Clean element-web (pnpm monorepo)
    echo "  Cleaning element-web..."
    rm -rf "$WEB_DIR/webapp"
    rm -rf "$WEB_DIR/lib"

    # Clean element-desktop (inside monorepo)
    echo "  Cleaning element-desktop..."
    rm -rf "$DESKTOP_DIR/dist"
    rm -rf "$DESKTOP_DIR/lib"
    rm -rf "$DESKTOP_DIR/webapp"
    rm -rf "$DESKTOP_DIR/webapp.asar"
    rm -rf "$DESKTOP_DIR/.hak"

    # Clean seshat
    echo "  Cleaning seshat..."
    rm -f "$SCRIPT_DIR/seshat/seshat-node/index.node"

    echo "  Clean complete"
fi

# 1. Check and install dependencies if needed
echo ""
echo "[1/6] Checking dependencies..."

# Install monorepo dependencies from root
cd "$ELEMENT_WEB_ROOT"
if [ ! -d "node_modules" ]; then
    echo "Installing monorepo dependencies..."
    pnpm install
elif [ "pnpm-lock.yaml" -nt "node_modules/.pnpm/lock.yaml" ] 2>/dev/null || [ "package.json" -nt "node_modules/.pnpm/lock.yaml" ] 2>/dev/null; then
    echo "Updating monorepo dependencies (pnpm-lock.yaml or package.json changed)..."
    pnpm install
else
    echo "Monorepo dependencies are up to date"
fi

echo "Dependencies OK"

# 2. Build seshat-node with bundled sqlcipher (static linking)
echo ""
echo "[2/6] Building seshat-node with bundled-sqlcipher..."
cd "$SCRIPT_DIR/seshat"
# Build from workspace root with bundled-sqlcipher feature
cargo build --release -p matrix-seshat --features bundled-sqlcipher
cp target/release/libmatrix_seshat.dylib seshat-node/index.node
SESHAT_INDEX_NODE="$SCRIPT_DIR/seshat/seshat-node/index.node"
echo "Built: $SESHAT_INDEX_NODE (with bundled sqlcipher)"

# Verify no dynamic sqlcipher dependency
if otool -L "$SESHAT_INDEX_NODE" | grep -q sqlcipher; then
    echo "WARNING: index.node still has dynamic sqlcipher dependency!"
    otool -L "$SESHAT_INDEX_NODE" | grep -i sql
else
    echo "OK: No dynamic sqlcipher dependency"
fi

# 3. Build element-web
echo ""
echo "[3/6] Building element-web..."
cd "$ELEMENT_WEB_ROOT"

# Build via pnpm (nx handles shared-components and other dependencies)
pnpm --filter element-web build
echo "Built: $WEB_DIR/webapp"

# 4. Package webapp as ASAR
echo ""
echo "[4/6] Packaging webapp as ASAR..."
cd "$DESKTOP_DIR"
rm -rf webapp webapp.asar
cp -r "$WEB_DIR/webapp" ./

# Add config.json if not present (required for default homeserver)
if [ ! -f webapp/config.json ]; then
    echo "Adding config.json to webapp..."
    if [ -f "$WEB_DIR/config.json" ]; then
        cp "$WEB_DIR/config.json" webapp/
    elif [ -f "$WEB_DIR/config.sample.json" ]; then
        cp "$WEB_DIR/config.sample.json" webapp/config.json
    else
        echo "WARNING: No config.json or config.sample.json found!"
    fi
fi

npx asar pack webapp webapp.asar
rm -rf webapp  # Clean up copied directory
echo "Created: webapp.asar"

# 5. Install local seshat-node to .hak/hakModules (electron-builder uses this)
# NOTE: electron-builder only packages from .hak/hakModules, NOT node_modules!
echo ""
echo "[5/6] Installing local seshat-node to .hak/hakModules..."

# Create hakModules directory structure
HAK_SESHAT_DIR=".hak/hakModules/matrix-seshat"
mkdir -p "$HAK_SESHAT_DIR"

# Copy necessary files from seshat-node
cp "$SCRIPT_DIR/seshat/seshat-node/index.node" "$HAK_SESHAT_DIR/"
cp "$SCRIPT_DIR/seshat/seshat-node/index.js" "$HAK_SESHAT_DIR/"
cp "$SCRIPT_DIR/seshat/seshat-node/package.json" "$HAK_SESHAT_DIR/"

# Verify the files are in place
echo "Installed to $HAK_SESHAT_DIR:"
ls -la "$HAK_SESHAT_DIR"

# Also copy to node_modules for development/testing
rm -rf node_modules/matrix-seshat
cp -r "$HAK_SESHAT_DIR" node_modules/matrix-seshat

echo "Installed seshat-node"

# 6. Build TypeScript and resources, then DMG
echo ""
echo "[6/6] Building DMG..."
pnpm run build:ts
pnpm run build:res

ELECTRON_BUILDER_ARGS=("$ARCH" "--mac" "dmg" "-c.npmRebuild=false")

# electron-builder 26+ uses actool for .icon (asset catalog) mac icons and requires
# actool >= 26 (Xcode 26). GitHub Actions macOS images ship older CLT actool (~16.x),
# which fails createMacApp and leaves an unrenamed Electron.app. Fall back to .icns.
if [ -n "${CI:-}" ]; then
    ELECTRON_BUILDER_ARGS+=("--publish" "never")
fi

USE_ICNS_FALLBACK=false
if ! command -v actool >/dev/null 2>&1 || ! actool --version >/dev/null 2>&1; then
    USE_ICNS_FALLBACK=true
else
    ACTOOL_VER=$(actool --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    ACTOOL_MAJOR="${ACTOOL_VER%%.*}"
    if [ "${ACTOOL_MAJOR:-0}" -lt 26 ] 2>/dev/null; then
        USE_ICNS_FALLBACK=true
    fi
fi

if [ "$USE_ICNS_FALLBACK" = true ]; then
    echo "actool missing or unsupported for .icon (need >= 26, found ${ACTOOL_VER:-none}); generating build/icon.icns fallback..."
    ICON_ICNS="$(ensure_icns_icon "$DESKTOP_DIR/build")"
    ELECTRON_BUILDER_ARGS+=("-c.mac.icon=$ICON_ICNS" "-c.dmg.badgeIcon=$ICON_ICNS")
fi

# Build DMG (skip rebuild to use our local seshat-node with bundled sqlcipher)
# Disable npm rebuild to prevent overwriting our index.node
npx electron-builder "${ELECTRON_BUILDER_ARGS[@]}"

echo ""
echo "========================================"
echo "Build complete!"
echo "DMG file: $DESKTOP_DIR/dist/"
ls -la "$DESKTOP_DIR/dist/"*.dmg 2>/dev/null | tail -5
echo "========================================"
