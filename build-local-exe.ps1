# Build Element Desktop exe with local seshat and element-web
# Usage: .\build-local-exe.ps1 [-NoClean] [-x64]
#
# Prerequisites: Git, Node, Python, Rust, Visual Studio Build Tools (see element-web/apps/desktop native build docs)
# Requires: Node.js v24 (v25+ has ESM/CJS compatibility issues with dependencies)
#
param(
    [switch]$NoClean,
    [switch]$x64
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DesktopDir = Join-Path $ScriptDir "element-web\apps\desktop"
$Clean = -not $NoClean

function Test-PnpmWorkspaceNeedsInstall {
    param([string]$ProjectRoot)
    $prev = Get-Location
    try {
        Set-Location $ProjectRoot
        if (-not (Test-Path "node_modules")) {
            return $true
        }
        $lockMarker = "node_modules\.pnpm\lock.yaml"
        if (-not (Test-Path $lockMarker)) {
            return $true
        }
        $lockYaml = Get-Item $lockMarker
        if (Test-Path "pnpm-lock.yaml") {
            $pnpmLock = Get-Item "pnpm-lock.yaml"
            if ($pnpmLock.LastWriteTime -gt $lockYaml.LastWriteTime) {
                return $true
            }
        }
        if (Test-Path "package.json") {
            $pkgJson = Get-Item "package.json"
            if ($pkgJson.LastWriteTime -gt $lockYaml.LastWriteTime) {
                return $true
            }
        }
        return $false
    }
    finally {
        Set-Location $prev
    }
}

Write-Host "========================================"
Write-Host "Building Element Desktop for Windows"
Write-Host "Architecture: $(if ($x64) { 'x64' } else { 'current' })"
Write-Host "Clean build: $(-not $NoClean)"
Write-Host "========================================"

# 0. Clean build artifacts if requested
if ($Clean) {
    Write-Host ""
    Write-Host "[0/6] Cleaning build artifacts..."

    # Clean element-web (pnpm monorepo)
    Write-Host "  Cleaning element-web..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$ScriptDir\element-web\apps\web\webapp"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$ScriptDir\element-web\apps\web\lib"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$ScriptDir\element-web\packages\shared-components\dist"

    # Clean element-desktop (pnpm package under element-web monorepo)
    Write-Host "  Cleaning element-web/apps/desktop..."
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$DesktopDir\dist"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$DesktopDir\lib"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$DesktopDir\webapp"
    Remove-Item -Force -ErrorAction SilentlyContinue "$DesktopDir\webapp.asar"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$DesktopDir\.hak"

    # Clean seshat
    Write-Host "  Cleaning seshat..."
    Remove-Item -Force -ErrorAction SilentlyContinue "$ScriptDir\seshat\seshat-node\index.node"

    Write-Host "  Clean complete"
}

# 1. Check dependencies
Write-Host ""
Write-Host "[1/6] Checking dependencies..."

Set-Location "$ScriptDir\element-web"
if (Test-PnpmWorkspaceNeedsInstall -ProjectRoot "$ScriptDir\element-web") {
    Write-Host "Installing or updating element-web dependencies (pnpm monorepo)..."
    pnpm install
}
else {
    Write-Host "element-web dependencies are up to date"
}

# apps/desktop is part of the element-web pnpm workspace; root install covers it.

Set-Location "$ScriptDir\seshat\seshat-node"
if (-not (Test-Path "node_modules")) {
    yarn install
}
else {
    Write-Host "seshat-node dependencies OK"
}

# 2. Build seshat-node with bundled sqlcipher
Write-Host ""
Write-Host "[2/6] Building seshat-node with bundled-sqlcipher..."
Set-Location "$ScriptDir\seshat\seshat-node"
yarn run build-bundled
$SESHAT_INDEX_NODE = "$ScriptDir\seshat\seshat-node\index.node"
if (-not (Test-Path $SESHAT_INDEX_NODE)) {
    throw "seshat-node build failed: index.node not found"
}
Write-Host "Built: $SESHAT_INDEX_NODE"

# 3. Build element-web (pnpm monorepo with nx)
Write-Host ""
Write-Host "[3/6] Building element-web..."
Set-Location "$ScriptDir\element-web"

# Build via pnpm (nx handles shared-components and other dependencies)
pnpm --filter element-web build
Write-Host "Built: $ScriptDir\element-web\apps\web\webapp"

# 4. Package webapp as ASAR
Write-Host ""
Write-Host "[4/6] Packaging webapp as ASAR..."
Set-Location $DesktopDir
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "webapp"
Remove-Item -Force -ErrorAction SilentlyContinue "webapp.asar"
Copy-Item -Recurse "$ScriptDir\element-web\apps\web\webapp" "webapp"

# Add config.json if not present
if (-not (Test-Path "webapp\config.json")) {
    Write-Host "Adding config.json to webapp..."
    if (Test-Path "..\web\config.json") {
        Copy-Item "..\web\config.json" "webapp\"
    } elseif (Test-Path "..\web\config.sample.json") {
        Copy-Item "..\web\config.sample.json" "webapp\config.json"
    } else {
        Write-Host "WARNING: No config.json or config.sample.json found!"
    }
}

npx asar pack webapp webapp.asar
Remove-Item -Recurse -Force "webapp"
Write-Host "Created: webapp.asar"

# 5. Install local seshat-node to .hak/hakModules
Write-Host ""
Write-Host "[5/6] Installing local seshat-node to .hak/hakModules..."
$HAK_SESHAT_DIR = ".hak\hakModules\matrix-seshat"
New-Item -ItemType Directory -Force -Path $HAK_SESHAT_DIR | Out-Null

Copy-Item "$ScriptDir\seshat\seshat-node\index.node" "$HAK_SESHAT_DIR\"
Copy-Item "$ScriptDir\seshat\seshat-node\index.js" "$HAK_SESHAT_DIR\"
Copy-Item "$ScriptDir\seshat\seshat-node\package.json" "$HAK_SESHAT_DIR\"

# Also copy to node_modules for development
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node_modules\matrix-seshat"
Copy-Item -Recurse $HAK_SESHAT_DIR "node_modules\matrix-seshat"

Write-Host "Installed seshat-node"

# 6. Build TypeScript, resources, then exe
Write-Host ""
Write-Host "[6/6] Building Windows exe..."
pnpm run build:ts
pnpm run build:res

# Build Windows package (--x64 for 64-bit, omit for default)
# squirrel = Element Setup.exe, msi = installer
# -c.npmRebuild=false prevents overwriting our custom index.node
$BuildArgs = @("--win", "-c.npmRebuild=false")
if ($x64) { $BuildArgs += "--x64" }
npx electron-builder @BuildArgs

Write-Host ""
Write-Host "========================================"
Write-Host "Build complete!"
Write-Host "Output: $DesktopDir\dist\"
Get-ChildItem "$DesktopDir\dist" -ErrorAction SilentlyContinue | Format-Table Name, Length -AutoSize
Write-Host "========================================"
