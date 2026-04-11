# Element-dev

Development environment for building Element Desktop with custom seshat (n-gram tokenizer support).

## Structure

```
Element-dev/
├── build-local-dmg.sh    # Build script (macOS)
├── build-local-exe.ps1   # Build script (Windows)
├── element-web/          # Submodule (shinaoka/tokenizer-mode-disable-auto-update branch)
├── element-desktop/      # Submodule (shinaoka/ngram branch)
└── seshat/               # Submodule (work/tokenizer-mode-switching branch)
```

## Setup

### Install Rust
```bash
$ curl https://sh.rustup.rs -sSf | sh -s -- -y
$ cargo --version
cargo 1.94.0 (85eff7c80 2026-01-15)
```

### Install Node.js using `nvm` with `pnpm`

```bash
$ curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
$ \. "$HOME/.nvm/nvm.sh"
$ nvm install 24
$ corepack enable pnpm
$ pnpm -v
10.28.1
```

### Clone `Element-dev`

```bash
$ git clone git@github.com:shinaoka/Element-dev.git
$ cd Elemnt-dev
# Clone submodules
$ git submodule update --init --recursive
```

## Build DMG (macOS)

```bash
# Build arm64 DMG (default)
./build-local-dmg.sh

# Build x64 DMG
./build-local-dmg.sh --x64

# Build universal DMG (requires both targets)
rustup target add x86_64-apple-darwin
./build-local-dmg.sh --universal
```

Output: `element-desktop/dist/Element-*.dmg`

## Build exe (Windows)

Prerequisites: [element-desktop/docs/windows-requirements.md](element-desktop/docs/windows-requirements.md)  
(Git, Node, Python, Rust, Visual Studio Build Tools, etc.)

```powershell
# Build exe (default architecture)
.\build-local-exe.ps1

# Build x64 exe explicitly
.\build-local-exe.ps1 -x64

# Skip clean (faster incremental build)
.\build-local-exe.ps1 -NoClean
```

Output: `element-desktop/dist/`  
- `Element Setup X.X.X.exe` (Squirrel installer)  
- `win-unpacked/Element.exe` (portable)

## Features

- **N-gram tokenizer**: Better search for CJK languages (Japanese, Chinese, Korean)
- **Bundled sqlcipher**: No external library dependencies
- **Tokenizer mode selection**: Settings → Security & Privacy → Message search

## Submodule Branches

| Repository | Branch |
|------------|--------|
| element-web | shinaoka/tokenizer-mode-disable-auto-update |
| element-desktop | shinaoka/ngram |
| seshat | work/tokenizer-mode-switching |
