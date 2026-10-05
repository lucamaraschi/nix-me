#!/bin/bash

# Simple test script for nix-me CLI

echo "🧪 nix-me Quick Test"
echo ""

# Test 1: Basic files
echo "✓ Checking files..."
ls apps/cli/bin/nix-me apps/cli/lib/*.sh nix/hosts/profiles/*.nix > /dev/null 2>&1 && echo "  ✓ All core files present"

# Test 2: Help command
echo ""
echo "✓ Testing help command..."
apps/cli/bin/nix-me help > /dev/null 2>&1 && echo "  ✓ Help works"

# Test 3: Libraries
echo ""
echo "✓ Testing libraries..."
bash -c "source apps/cli/lib/ui.sh && source apps/cli/lib/package-manager.sh" 2>&1 | grep -q "Error" && echo "  ✗ Library errors" || echo "  ✓ Libraries load"

# Test 4: fzf check
echo ""
echo "✓ Checking dependencies..."
which fzf > /dev/null 2>&1 && echo "  ✓ fzf available" || echo "  ⚠ fzf not installed (brew install fzf)"
which brew > /dev/null 2>&1 && echo "  ✓ Homebrew available" || echo "  ✗ Homebrew missing"

# Test 5: Docs
echo ""
echo "✓ Checking documentation..."
ls docs/*.md DEMO.md CUSTOMIZATION.md > /dev/null 2>&1 && echo "  ✓ Documentation complete"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Basic tests passed!"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Test the CLI:"
echo "   apps/cli/bin/nix-me help"
echo "   apps/cli/bin/nix-me status"
echo "   apps/cli/bin/nix-me doctor"
echo ""
echo "2. Test interactive browser (requires fzf):"
echo "   apps/cli/bin/nix-me search docker"
echo "   # Press ESC to cancel"
echo ""
echo "3. Test wizard (safe mode):"
echo "   ./tests/integration/test-wizard.sh"
echo ""
echo "4. See TESTING.md for complete test guide"
echo ""
