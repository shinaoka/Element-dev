#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"

cat >"$TEST_DIR/bin/pnpm" <<'EOF'
#!/bin/bash
echo "pnpm $*" >>"$TEST_BIN_LOG"
exit 0
EOF

cat >"$TEST_DIR/bin/yarn" <<'EOF'
#!/bin/bash
echo "yarn $*" >>"$TEST_BIN_LOG"
exit 42
EOF

cat >"$TEST_DIR/bin/cargo" <<'EOF'
#!/bin/bash
exit 99
EOF

chmod +x "$TEST_DIR/bin/pnpm" "$TEST_DIR/bin/yarn" "$TEST_DIR/bin/cargo"

cp "$ROOT_DIR/build-local-dmg.sh" "$TEST_DIR/"

mkdir -p "$TEST_DIR/element-web/node_modules/.pnpm"
mkdir -p "$TEST_DIR/element-desktop"
mkdir -p "$TEST_DIR/seshat"

cat >"$TEST_DIR/element-web/package.json" <<'EOF'
{"name":"element-web-monorepo","packageManager":"pnpm@10.29.3"}
EOF

cat >"$TEST_DIR/element-web/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'
EOF

cat >"$TEST_DIR/element-web/node_modules/.pnpm/lock.yaml" <<'EOF'
lockfileVersion: '9.0'
EOF

cat >"$TEST_DIR/element-desktop/package.json" <<'EOF'
{"name":"element-desktop","packageManager":"pnpm@10.32.1"}
EOF

cat >"$TEST_DIR/element-desktop/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'
EOF

touch -r "$TEST_DIR/element-web/pnpm-lock.yaml" "$TEST_DIR/element-web/package.json"
touch "$TEST_DIR/element-web/node_modules/.pnpm/lock.yaml"

LOG_FILE="$TEST_DIR/commands.log"
export TEST_BIN_LOG="$LOG_FILE"

set +e
(
    cd "$TEST_DIR"
    PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash ./build-local-dmg.sh
)
status=$?
set -e

if [[ $status -ne 99 ]]; then
    echo "expected build-local-dmg.sh to stop at fake cargo with exit 99, got $status"
    cat "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

if grep -q '^yarn ' "$LOG_FILE" 2>/dev/null; then
    echo "build-local-dmg.sh unexpectedly invoked yarn"
    cat "$LOG_FILE"
    exit 1
fi

if ! grep -q '^pnpm install$' "$LOG_FILE" 2>/dev/null; then
    echo "build-local-dmg.sh did not invoke pnpm install for element-desktop"
    cat "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

echo "PASS: build-local-dmg.sh used pnpm for element-desktop dependencies"
