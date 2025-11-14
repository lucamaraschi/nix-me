#!/bin/bash

# Test wizard in safe mode
# This will run through the wizard but not apply changes

echo "🧪 Testing nix-me wizard (safe mode)"
echo ""
echo "This will run the wizard but NOT apply any changes"
echo "Press Ctrl+C at any time to exit"
echo ""
read -p "Press ENTER to start..."

# Set test mode
export CONFIG_DIR="/tmp/nix-me-test-$$"
mkdir -p "$CONFIG_DIR"

# Copy minimal required files
cp -r lib "$CONFIG_DIR/../lib"
cp flake.nix "$CONFIG_DIR/"
mkdir -p "$CONFIG_DIR/hosts/profiles"
cp hosts/profiles/*.nix "$CONFIG_DIR/hosts/profiles/" 2>/dev/null || true

echo ""
echo "Test config directory: $CONFIG_DIR"
echo ""

# Run wizard
bin/nix-me create

echo ""
echo "✓ Wizard test complete!"
echo ""
echo "Test config created at: $CONFIG_DIR"
echo "To clean up: rm -rf $CONFIG_DIR"
