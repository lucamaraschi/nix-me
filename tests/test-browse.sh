#!/bin/bash

# Test the interactive browser
# This is safe - it will show the UI but you can cancel without applying

echo "🔍 Testing interactive package browser"
echo ""
echo "Requirements:"
echo "  - fzf (fuzzy finder)"
echo "  - Homebrew (for searching packages)"
echo ""

# Check fzf
if ! command -v fzf &>/dev/null; then
    echo "❌ fzf not found"
    echo ""
    echo "Install fzf first:"
    echo "  brew install fzf"
    echo "  OR"
    echo "  nix-shell -p fzf"
    exit 1
fi

echo "✓ fzf found"

# Check brew
if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew not found"
    echo ""
    echo "Homebrew is required for package browsing"
    exit 1
fi

echo "✓ Homebrew found"
echo ""
echo "Testing search functionality..."
echo ""

# Test search (you can cancel with ESC)
echo "Searching for 'docker' apps..."
echo "(Press ESC to cancel, or select and confirm to see how it works)"
echo ""

# Source the library
source lib/ui.sh
source lib/package-manager.sh

# Run search
browse_homebrew_casks_fzf "docker"

echo ""
echo "✓ Browser test complete!"
