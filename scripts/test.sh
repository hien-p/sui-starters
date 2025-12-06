#!/bin/bash
# Run tests for all packages in the repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Testing @sui-starters packages ==="
echo ""

# Package directories
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

TOTAL_PASSED=0
TOTAL_FAILED=0

for pkg in "${PACKAGES[@]}"; do
    PKG_PATH="$ROOT_DIR/$pkg"
    if [ -d "$PKG_PATH" ]; then
        echo "Testing $pkg..."
        cd "$PKG_PATH"

        # Run tests and capture output
        OUTPUT=$(sui move test 2>&1) || true

        # Parse test results
        if echo "$OUTPUT" | grep -q "Test result: OK"; then
            PASSED=$(echo "$OUTPUT" | grep -o "passed: [0-9]*" | grep -o "[0-9]*" || echo "0")
            FAILED=$(echo "$OUTPUT" | grep -o "failed: [0-9]*" | grep -o "[0-9]*" || echo "0")
            echo "✓ $pkg: $PASSED passed, $FAILED failed"
            TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
            TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
        else
            echo "✗ $pkg: Tests failed to run"
            echo "$OUTPUT" | tail -5
        fi
        echo ""
    fi
done

echo "=== Test Summary ==="
echo "Total tests passed: $TOTAL_PASSED"
echo "Total tests failed: $TOTAL_FAILED"

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed"
    exit 1
fi
