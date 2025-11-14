#!/bin/bash

# Automated test runner for nix-me CLI
# Tests all non-interactive features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}  ✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}  ✗${NC} $1"
    ((FAILED++))
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
}

# Start tests
print_header "nix-me CLI Test Suite"

# Test 1: Check files exist
print_test "Checking required files exist"

if [ -f "bin/nix-me" ]; then
    print_pass "bin/nix-me exists"
else
    print_fail "bin/nix-me not found"
fi

if [ -x "bin/nix-me" ]; then
    print_pass "bin/nix-me is executable"
else
    print_fail "bin/nix-me not executable"
    chmod +x bin/nix-me
    print_pass "Fixed: made bin/nix-me executable"
fi

for lib in ui.sh config-builder.sh wizard.sh config-wizard.sh package-manager.sh; do
    if [ -f "lib/$lib" ]; then
        print_pass "lib/$lib exists"
    else
        print_fail "lib/$lib not found"
    fi
done

# Test 2: Check libraries load
print_test "Testing library loading"

if source lib/ui.sh 2>/dev/null; then
    print_pass "ui.sh loads without errors"
else
    print_fail "ui.sh failed to load"
fi

if source lib/config-builder.sh 2>/dev/null; then
    print_pass "config-builder.sh loads without errors"
else
    print_fail "config-builder.sh failed to load"
fi

if source lib/package-manager.sh 2>/dev/null; then
    print_pass "package-manager.sh loads without errors"
else
    print_fail "package-manager.sh failed to load"
fi

if source lib/config-wizard.sh 2>/dev/null; then
    print_pass "config-wizard.sh loads without errors"
else
    print_fail "config-wizard.sh failed to load"
fi

# Test 3: Check profile files exist
print_test "Checking profile configurations"

if [ -f "hosts/profiles/work.nix" ]; then
    print_pass "Work profile exists"
else
    print_fail "Work profile not found"
fi

if [ -f "hosts/profiles/personal.nix" ]; then
    print_pass "Personal profile exists"
else
    print_fail "Personal profile not found"
fi

if [ -f "hosts/macbook-pro/default.nix" ]; then
    print_pass "MacBook Pro machine type exists"
else
    print_fail "MacBook Pro machine type not found"
fi

# Test 4: Test CLI commands (help)
print_test "Testing CLI help command"

if bin/nix-me help &>/dev/null; then
    print_pass "help command works"
else
    print_fail "help command failed"
fi

if bin/nix-me --help &>/dev/null; then
    print_pass "--help flag works"
else
    print_fail "--help flag failed"
fi

# Test 5: Test CLI unknown command handling
print_test "Testing error handling"

if bin/nix-me invalid-command 2>&1 | grep -q "Unknown command"; then
    print_pass "Unknown command error handled correctly"
else
    print_fail "Unknown command error not handled"
fi

# Test 6: Check documentation
print_test "Checking documentation files"

for doc in docs/CLI_GUIDE.md docs/QUICK_REFERENCE.md docs/PROFILES.md DEMO.md CUSTOMIZATION.md NEW_FEATURES.md; do
    if [ -f "$doc" ]; then
        print_pass "$doc exists"
    else
        print_fail "$doc not found"
    fi
done

# Test 7: Check flake syntax
print_test "Validating flake.nix syntax"

if nix flake check --extra-experimental-features "nix-command flakes" 2>&1 | grep -q "checking"; then
    print_pass "flake.nix syntax valid"
else
    print_fail "flake.nix has syntax errors"
fi

# Test 8: Check for fzf (optional)
print_test "Checking optional dependencies"

if command -v fzf &>/dev/null; then
    print_pass "fzf is installed (interactive features available)"
else
    echo -e "${YELLOW}  ⚠${NC} fzf not installed (interactive features limited)"
    echo -e "${YELLOW}    Install with: brew install fzf${NC}"
fi

if command -v brew &>/dev/null; then
    print_pass "Homebrew is installed"
else
    print_fail "Homebrew not found (required for package browsing)"
fi

# Test 9: Test color output
print_test "Testing color support"

if echo -e "\033[0;32mtest\033[0m" | grep -q "test"; then
    print_pass "Color codes supported"
else
    print_fail "Color codes not working"
fi

# Test 10: Test function exports
print_test "Testing exported functions"

source lib/package-manager.sh

if declare -f browse_homebrew_casks_fzf &>/dev/null; then
    print_pass "browse_homebrew_casks_fzf function exported"
else
    print_fail "browse_homebrew_casks_fzf not exported"
fi

if declare -f has_fzf &>/dev/null; then
    print_pass "has_fzf function exported"
else
    print_fail "has_fzf not exported"
fi

# Summary
print_header "Test Results"

TOTAL=$((PASSED + FAILED))
PASS_RATE=$((PASSED * 100 / TOTAL))

echo "Total tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    echo ""
    echo -e "${RED}Some tests failed. Review errors above.${NC}"
    exit 1
else
    echo -e "${GREEN}Failed: 0${NC}"
    echo ""
    echo -e "${GREEN}✅ All tests passed! ($PASS_RATE%)${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test interactive features:"
    echo "     ./tests/test-browse.sh    # Test fzf browser"
    echo "     ./tests/test-wizard.sh    # Test wizard"
    echo ""
    echo "  2. Try the CLI:"
    echo "     bin/nix-me help"
    echo "     bin/nix-me doctor"
    echo "     bin/nix-me browse   # Requires fzf"
    echo ""
    echo "  3. See TESTING.md for full test guide"
    exit 0
fi
