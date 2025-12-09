#!/bin/bash
# Build Element Desktop DMG with local seshat and element-web
# Usage: ./build-local-dmg.sh [--arm64|--x64|--universal]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="${1:---arm64}"  # Default to arm64

echo "========================================"
echo "Building Element Desktop DMG"
echo "Architecture: $ARCH"
echo "========================================"

# 1. Build seshat-node with bundled sqlcipher (static linking)
echo ""
echo "[1/5] Building seshat-node with bundled-sqlcipher..."
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

# 2. Build element-web
echo ""
echo "[2/5] Building element-web..."
cd "$SCRIPT_DIR/element-web"
yarn build
echo "Built: $SCRIPT_DIR/element-web/webapp"

# 3. Package webapp as ASAR
echo ""
echo "[3/5] Packaging webapp as ASAR..."
cd "$SCRIPT_DIR/element-desktop"
rm -rf webapp webapp.asar
cp -r ../element-web/webapp ./
npx asar pack webapp webapp.asar
rm -rf webapp  # Clean up copied directory
echo "Created: webapp.asar"

# 4. Install local seshat-node to .hak/hakModules (electron-builder uses this)
# NOTE: electron-builder only packages from .hak/hakModules, NOT node_modules!
echo ""
echo "[4/5] Installing local seshat-node to .hak/hakModules..."

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

# 5. Build TypeScript and resources
echo ""
echo "[5/5] Building DMG..."
yarn run build:ts
yarn run build:res

# Build DMG (skip rebuild to use our local seshat-node with bundled sqlcipher)
# Disable npm rebuild to prevent overwriting our index.node
npx electron-builder $ARCH --mac dmg -c.npmRebuild=false || true  # Ignore GH_TOKEN error

echo ""
echo "========================================"
echo "Build complete!"
echo "DMG file: $SCRIPT_DIR/element-desktop/dist/"
ls -la "$SCRIPT_DIR/element-desktop/dist/"*.dmg 2>/dev/null | tail -5
echo "========================================"
