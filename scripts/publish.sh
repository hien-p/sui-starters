#!/bin/bash
# Publish packages to Sui network
# Usage: ./publish.sh <package> [network]
# Example: ./publish.sh core testnet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PACKAGE="${1:-}"
NETWORK="${2:-testnet}"
GAS_BUDGET="${3:-100000000}"

if [ -z "$PACKAGE" ]; then
    echo "Usage: $0 <package> [network] [gas_budget]"
    echo "Example: $0 core testnet 100000000"
    echo ""
    echo "Available packages:"
    ls -1 "$ROOT_DIR/packages"
    exit 1
fi

PKG_PATH="$ROOT_DIR/packages/$PACKAGE"

if [ ! -d "$PKG_PATH" ]; then
    echo "Error: Package '$PACKAGE' not found at $PKG_PATH"
    exit 1
fi

echo "=== Publishing @sui-starters/$PACKAGE ==="
echo "Network: $NETWORK"
echo "Gas Budget: $GAS_BUDGET"
echo ""

# Switch to network
echo "Switching to $NETWORK..."
sui client switch --env "$NETWORK" || true

# Build first
echo "Building package..."
cd "$PKG_PATH"
sui move build

# Publish
echo ""
echo "Publishing..."
sui client publish --gas-budget "$GAS_BUDGET"

echo ""
echo "=== Publication Complete ==="
echo "Save the package ID for MVR registration!"
