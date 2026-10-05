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
mkdir -p "$CONFIG_DIR/apps/cli"
cp -r apps/cli/lib "$CONFIG_DIR/apps/cli/lib"
mkdir -p "$CONFIG_DIR/apps/cli/bin"
cp apps/cli/bin/nix-me "$CONFIG_DIR/apps/cli/bin/nix-me"
cp flake.nix "$CONFIG_DIR/"
mkdir -p "$CONFIG_DIR/nix/hosts/profiles"
cp nix/hosts/profiles/*.nix "$CONFIG_DIR/nix/hosts/profiles/" 2>/dev/null || true

echo ""
echo "Test config directory: $CONFIG_DIR"
echo ""

# Run wizard
apps/cli/bin/nix-me create

echo ""
echo "✓ Wizard test complete!"
echo ""
echo "Test config created at: $CONFIG_DIR"
echo "To clean up: rm -rf $CONFIG_DIR"
