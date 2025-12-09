# Element-dev

Development environment for building Element Desktop with custom seshat (n-gram tokenizer support).

## Structure

```
Element-dev/
├── build-local-dmg.sh    # Build script
├── element-web/          # Submodule (shinaoka/ngram branch)
├── element-desktop/      # Submodule (shinaoka/ngram branch)
└── seshat/               # Submodule (work/tokenizer-mode-switching branch)
```

## Setup

```bash
# Clone with submodules
git clone --recursive git@github.com:shinaoka/Element-dev.git

# Or if already cloned
git submodule update --init --recursive

# Install dependencies
cd element-web && yarn install && cd ..
cd element-desktop && yarn install && cd ..
cd seshat/seshat-node && yarn install && cd ../..
```

## Build DMG

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

## Features

- **N-gram tokenizer**: Better search for CJK languages (Japanese, Chinese, Korean)
- **Bundled sqlcipher**: No external library dependencies
- **Tokenizer mode selection**: Settings → Security & Privacy → Message search

## Submodule Branches

| Repository | Branch |
|------------|--------|
| element-web | shinaoka/ngram |
| element-desktop | shinaoka/ngram |
| seshat | work/tokenizer-mode-switching |
