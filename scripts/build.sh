#!/bin/bash
# Build all packages in the repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Building @sui-starters packages ==="
echo ""

# Build packages
PACKAGES=(
    "packages/core"
    "packages/access"
    "packages/events"
    "packages/nft"
    "packages/token"
    "packages/defi"
    "packages/escrow"
    "packages/gaming"
    "packages/governance"
    "packages/staking"
    "packages/launchpad"
)

FAILED=0

for pkg in "${PACKAGES[@]}"; do
    PKG_PATH="$ROOT_DIR/$pkg"
    if [ -d "$PKG_PATH" ]; then
        echo "Building $pkg..."
        if cd "$PKG_PATH" && sui move build 2>&1 | grep -v "^warning" | grep -v "^$"; then
            echo "✓ $pkg built successfully"
        else
            echo "✗ $pkg build failed"
            FAILED=$((FAILED + 1))
        fi
        echo ""
    fi
done

echo "=== Build Summary ==="
if [ $FAILED -eq 0 ]; then
    echo "All packages built successfully!"
else
    echo "$FAILED package(s) failed to build"
    exit 1
fi
