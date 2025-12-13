#!/bin/bash
# Build Element Desktop DMG with local seshat and element-web
# Usage: ./build-local-dmg.sh [--no-clean] [--arm64|--x64|--universal]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEAN=true  # Default to clean build
ARCH="--arm64"  # Default to arm64

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
echo "Building Element Desktop DMG"
echo "Architecture: $ARCH"
echo "Clean build: $CLEAN"
echo "========================================"

# 0. Clean build artifacts if requested
if [ "$CLEAN" = true ]; then
    echo ""
    echo "[0/6] Cleaning build artifacts..."
    
    # Clean element-web
    echo "  Cleaning element-web..."
    rm -rf "$SCRIPT_DIR/element-web/webapp"
    rm -rf "$SCRIPT_DIR/element-web/lib"
    rm -rf "$SCRIPT_DIR/element-web/packages/shared-components/dist"
    
    # Clean element-desktop
    echo "  Cleaning element-desktop..."
    rm -rf "$SCRIPT_DIR/element-desktop/dist"
    rm -rf "$SCRIPT_DIR/element-desktop/lib"
    rm -rf "$SCRIPT_DIR/element-desktop/webapp"
    rm -rf "$SCRIPT_DIR/element-desktop/webapp.asar"
    rm -rf "$SCRIPT_DIR/element-desktop/.hak"
    
    # Clean seshat
    echo "  Cleaning seshat..."
    rm -f "$SCRIPT_DIR/seshat/seshat-node/index.node"
    
    echo "  Clean complete"
fi

# 1. Check and install dependencies if needed
echo ""
echo "[1/6] Checking dependencies..."

# Check if element-web dependencies need updating
cd "$SCRIPT_DIR/element-web"
if [ ! -d "node_modules" ]; then
    echo "Installing element-web dependencies..."
    yarn install
elif [ "yarn.lock" -nt "node_modules/.yarn-integrity" ] 2>/dev/null || [ "package.json" -nt "node_modules/.yarn-integrity" ] 2>/dev/null; then
    echo "Updating element-web dependencies (yarn.lock or package.json changed)..."
    yarn install --check-files
else
    echo "element-web dependencies are up to date"
fi

# Check if element-desktop dependencies need updating
cd "$SCRIPT_DIR/element-desktop"
if [ ! -d "node_modules" ]; then
    echo "Installing element-desktop dependencies..."
    yarn install
elif [ "yarn.lock" -nt "node_modules/.yarn-integrity" ] 2>/dev/null || [ "package.json" -nt "node_modules/.yarn-integrity" ] 2>/dev/null; then
    echo "Updating element-desktop dependencies (yarn.lock or package.json changed)..."
    yarn install --check-files
else
    echo "element-desktop dependencies are up to date"
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

# 3. Build shared-components and element-web
echo ""
echo "[3/6] Building element-web..."
cd "$SCRIPT_DIR/element-web"

# Check if shared-components needs rebuild
SHARED_COMPONENTS_DIR="packages/shared-components"
SHARED_COMPONENTS_DIST="$SHARED_COMPONENTS_DIR/dist/element-web-shared-components.mjs"
NEEDS_REBUILD=false

if [ ! -f "$SHARED_COMPONENTS_DIST" ]; then
    echo "shared-components: dist not found, rebuilding..."
    NEEDS_REBUILD=true
else
    # Check if any source file is newer than dist
    NEWEST_SRC=$(find "$SHARED_COMPONENTS_DIR/src" -type f \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
    if [ -n "$NEWEST_SRC" ] && [ "$NEWEST_SRC" -nt "$SHARED_COMPONENTS_DIST" ]; then
        echo "shared-components: source files changed, rebuilding..."
        NEEDS_REBUILD=true
    fi
fi

if [ "$NEEDS_REBUILD" = true ]; then
    echo "Rebuilding shared-components..."
    (cd "$SHARED_COMPONENTS_DIR" && yarn prepare)
else
    echo "shared-components: up to date"
fi

yarn build
echo "Built: $SCRIPT_DIR/element-web/webapp"

# 4. Package webapp as ASAR
echo ""
echo "[4/6] Packaging webapp as ASAR..."
cd "$SCRIPT_DIR/element-desktop"
rm -rf webapp webapp.asar
cp -r ../element-web/webapp ./

# Add config.json if not present (required for default homeserver)
if [ ! -f webapp/config.json ]; then
    echo "Adding config.json to webapp..."
    if [ -f ../element-web/config.json ]; then
        cp ../element-web/config.json webapp/
    elif [ -f ../element-web/config.sample.json ]; then
        cp ../element-web/config.sample.json webapp/config.json
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
