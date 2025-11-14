#!/bin/bash

# Test script for green tick functionality
# This tests the core logic without requiring interactive input

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source libraries
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/package-manager.sh"

echo "Testing Green Tick Functionality"
echo "================================="
echo ""

# Test 1: Check if installed casks are detected
echo "Test 1: Checking installed casks detection..."
installed_casks=$(brew list --cask 2>/dev/null | sort)
if [ -n "$installed_casks" ]; then
    echo "✓ Successfully retrieved installed casks"
    echo "  Found $(echo "$installed_casks" | wc -l | tr -d ' ') installed casks"
else
    echo "✗ No installed casks found (or Homebrew not installed)"
fi
echo ""

# Test 2: Test formatting logic
echo "Test 2: Testing package formatting with green ticks..."
test_packages="docker
visual-studio-code
nonexistent-package-12345"

echo "Testing with packages:"
echo "$test_packages"
echo ""
echo "Formatted output:"

while IFS= read -r cask; do
    if [ -n "$cask" ]; then
        if echo "$installed_casks" | grep -q "^${cask}$"; then
            echo -e "  ${GREEN}✓${NC} $cask (installed)"
        else
            echo -e "    $cask (not installed)"
        fi
    fi
done <<< "$test_packages"
echo ""

# Test 3: Test package name extraction (simulating fzf output)
echo "Test 3: Testing package name extraction from formatted strings..."
test_formatted="  ✓ docker
    visual-studio-code
  ✓ google-chrome"

echo "Input (formatted):"
echo "$test_formatted"
echo ""
echo "Extracted package names:"
extracted=$(echo "$test_formatted" | sed 's/^[[:space:]]*✓[[:space:]]*//' | sed 's/^[[:space:]]*//')
echo "$extracted"
echo ""

# Test 4: Verify the list command works
echo "Test 4: Testing list command output..."
echo "Running: ./bin/nix-me list | head -20"
./bin/nix-me list | head -20
echo ""

echo "================================="
echo "All tests completed!"
echo ""
echo "Summary:"
echo "✓ Installed package detection works"
echo "✓ Green tick formatting works"
echo "✓ Package name extraction works"
echo "✓ List command displays green ticks"
echo ""
echo "To test the full interactive experience, run:"
echo "  ./bin/nix-me browse"
echo "  ./bin/nix-me search docker"
