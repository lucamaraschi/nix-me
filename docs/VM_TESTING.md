# Automated VM Testing for nix-me

This document describes the automated VM testing system for nix-me using UTM virtual machines.

## Overview

The VM testing system creates ephemeral macOS virtual machines to test the complete nix-me installation process in an isolated environment. This ensures:

- Installation works on clean macOS systems
- No dependency on host machine configuration
- Reproducible test environment
- Safe testing without affecting your main system

## Architecture

```
┌─────────────────────────────────────────────────┐
│  1. Clone base VM → Test VM                    │
│  2. Start Test VM                               │
│  3. Wait for VM to be ready (guest agent)       │
│  4. Clone nix-me from GitHub or copy local      │
│  5. Execute install.sh in VM                    │
│  6. Run verification tests                      │
│  7. Stop VM and cleanup                         │
└─────────────────────────────────────────────────┘
```

## Prerequisites

### 1. UTM Installation

Install UTM (macOS virtualization):

```bash
brew install --cask utm
# OR download from https://mac.getutm.app/
```

### 2. Base VM Setup

You need a base macOS VM with:

1. **Clean macOS installation** (Ventura, Sonoma, or Sequoia)
2. **Remote Login (SSH) enabled** - System Settings → Sharing → Remote Login
3. **Network connectivity** configured (Shared Network in UTM)
4. **User account** set up with sudo access

**Important:** No Homebrew or guest agent needed - keeps the VM truly clean to test complete installation flow!

#### Creating the Base VM

**Quick Setup (Automated)** ⭐

1. Create a fresh macOS VM in UTM:
   - Use "Virtualize" mode (faster, requires macOS 12+)
   - Allocate at least 4GB RAM, 2 CPU cores
   - 64GB+ disk space recommended

2. Install macOS and complete setup wizard

3. **Enable Remote Login:**
   - System Settings → General → Sharing
   - Turn on "Remote Login"

4. **Run automated setup:**
   ```bash
   ./tests/setup-base-vm-ssh.sh --vm="macOS Tahoe - base" --user=admin
   ```

Done! The script configures system settings via SSH (no software installed - keeps VM clean).

**Manual Setup (Alternative)**

If you prefer manual setup, see the detailed steps in [BASE_VM_SETUP.md](./BASE_VM_SETUP.md).

1. Open UTM and create a new macOS VM
2. Install macOS
3. Inside the VM, run:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/lucamaraschi/nix-me/main/tests/setup-base-vm.sh | bash
   ```
4. Shut down the VM

See [Base VM Setup Guide](./BASE_VM_SETUP.md) for complete instructions.

## Usage

### Basic Usage

Test the latest version from GitHub:

```bash
./tests/vm-test.sh --vm-user=admin
```

**Note:** `--vm-user` is required (the username in your base VM with SSH access).

This will:
1. Clone your base VM (default: "macOS Tahoe - base")
2. Create a test VM with a random name (nix-me-test-YYYYMMDD-HHMMSS-RANDOM)
3. Start the test VM and wait for SSH connectivity
4. Install nix-me from GitHub via SSH (including Homebrew)
5. Run verification tests
6. Ask if you want to keep or delete the VM

### Using a Different Base VM

If your base VM has a different name:

```bash
./tests/vm-test.sh --vm-user=admin --base-vm="macOS Sonoma Clean"
```

### Custom Test VM Name

Specify a custom name for the test VM:

```bash
./tests/vm-test.sh --vm-user=admin --name="my-test-vm"
```

### Test Local Changes

Test uncommitted changes in your working directory:

```bash
./tests/vm-test.sh --vm-user=admin --source=local
```

This will copy your local project files to the VM via SSH and run the installation from there. Perfect for testing changes before committing!

### Cleanup Strategies

Control VM cleanup with `--onsuccess` and `--onfailure` flags:

```bash
# Delete VM if tests pass, keep if they fail
./tests/vm-test.sh --vm-user=admin --onsuccess=delete --onfailure=keep

# Always keep VM for inspection
./tests/vm-test.sh --vm-user=admin --onsuccess=keep --onfailure=keep

# Always delete (good for CI)
./tests/vm-test.sh --vm-user=admin --onsuccess=delete --onfailure=delete

# Ask in both cases (default)
./tests/vm-test.sh --vm-user=admin --onsuccess=ask --onfailure=ask
```

### Combined Flags

Flags can be combined for precise control:

```bash
# Test local changes, auto-delete on success
./tests/vm-test.sh --vm-user=admin --source=local --onsuccess=delete

# Test GitHub version, keep on failure for debugging
./tests/vm-test.sh --vm-user=admin --source=github --onfailure=keep

# Use custom base VM with specific test name
./tests/vm-test.sh --vm-user=admin --base-vm="macOS Sonoma" --name="integration-test-1"

# Test with verbose logging and custom cleanup
./tests/vm-test.sh --vm-user=admin --verbose --source=github --onsuccess=delete --onfailure=keep

# Full custom setup with SSH key
./tests/vm-test.sh --vm-user=admin --ssh-key=~/.ssh/id_rsa --base-vm="My Base VM" --name="test-pr-123" --source=github --onsuccess=delete
```

### Legacy Flags

Old flag format still works for backward compatibility (but `--vm-user` is still required):

```bash
./tests/vm-test.sh --vm-user=admin --local    # Same as --source=local
./tests/vm-test.sh --vm-user=admin --keep     # Keep regardless of result
./tests/vm-test.sh --vm-user=admin --delete   # Delete regardless of result
```

## Verification Tests

The script runs the following verification tests:

1. **Nix Installation** - Checks if `nix` command is available
2. **darwin-rebuild** - Checks if nix-darwin is installed
3. **Config Directory** - Verifies `~/.config/nixpkgs` exists
4. **Flake Configuration** - Checks if `flake.nix` is present
5. **nix-me CLI** - Verifies the `nix-me` command is available

## Common Issues

### VM Won't Start

**Symptom:** VM fails to start or times out

**Solutions:**
- Ensure base VM is shut down (not suspended)
- Check that UTM is not running another instance
- Verify you have enough system resources (RAM, disk)

### SSH Connection Failed

**Symptom:** "Could not connect to VM via SSH" or "SSH connection timed out"

**Solutions:**
- Ensure Remote Login is enabled in base VM (System Settings → Sharing → Remote Login)
- Check VM network connectivity and IP address
- Verify SSH credentials (username/password or SSH key)
- Try increasing `SSH_TIMEOUT` in the script
- Manually test SSH: `ssh admin@$(utmctl ip-address "VM Name")`

### Installation Timeout

**Symptom:** "Installation timed out after 1800s"

**Solutions:**
- Slow first-time installation is normal (30+ minutes)
- Increase `INSTALL_TIMEOUT` in script if needed
- Check VM network connectivity
- Inspect VM manually to see installation progress

### Tests Fail

**Symptom:** Verification tests fail after installation

**Solutions:**
- Keep the VM (`--keep`) and inspect manually
- Check installation logs
- Verify network connectivity in VM
- Ensure base VM has sufficient disk space

## Configuration

### Command-line Configuration

```bash
# Specify base VM to clone and VM user
./tests/vm-test.sh --vm-user=admin --base-vm="Your Base VM Name"

# Specify test VM name
./tests/vm-test.sh --vm-user=admin --name="your-test-name"

# Use SSH key for authentication
./tests/vm-test.sh --vm-user=admin --ssh-key=~/.ssh/id_rsa
```

### Script Configuration

Edit `tests/vm-test.sh` to customize timeouts:

```bash
# Timeouts
VM_TIMEOUT=300        # 5 minutes for VM to start
INSTALL_TIMEOUT=1800  # 30 minutes for installation
```

Default base VM name if not specified: `macOS Tahoe - base`
Default test VM name format: `nix-me-test-YYYYMMDD-HHMMSS-RANDOM`

## Continuous Integration

### GitHub Actions (Future)

The VM test script can be integrated with GitHub Actions using:
- macOS runners with virtualization enabled
- Tart or similar macOS VM tools
- Self-hosted runners with UTM

Example workflow:

```yaml
name: VM Integration Tests
on: [push, pull_request]

jobs:
  vm-test:
    runs-on: macos-13
    steps:
      - uses: actions/checkout@v3
      - name: Setup UTM
        run: brew install --cask utm
      - name: Run VM tests
        run: ./tests/vm-test.sh --delete
```

## Troubleshooting

### Manual VM Cleanup

List all test VMs:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl list | grep nix-me-test
```

Delete a specific test VM:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl delete "nix-me-test-YYYYMMDD-HHMMSS"
```

### Access VM Console

1. Open UTM application
2. Find your test VM
3. Right-click → Show
4. View console output or interact with the VM

### Check SSH Connectivity

Test SSH connection to your VM:

```bash
# Get VM IP
/Applications/UTM.app/Contents/MacOS/utmctl ip-address "macOS Tahoe - base"

# Test SSH connection
ssh -o ConnectTimeout=10 admin@<VM_IP> "echo 'SSH working!'"

# Check Remote Login status inside VM
ssh admin@<VM_IP> "sudo systemsetup -getremotelogin"
```

## Advanced Usage

### Custom Test Scripts

You can extend the VM testing with custom scripts:

1. Create a test script in `tests/vm-tests/`
2. Modify `run_verification()` in `vm-test.sh`
3. Add your custom test logic

Example:

```bash
# Test 6: Check if specific apps are installed
tests_total=$((tests_total + 1))
if vm_exec "test -d /Applications/Visual\ Studio\ Code.app" &>/dev/null; then
    log "✓ VS Code is installed"
    tests_passed=$((tests_passed + 1))
else
    error "✗ VS Code not found"
fi
```

### Parallel Testing

Run multiple VM tests in parallel:

```bash
# Terminal 1
./tests/vm-test.sh --delete &

# Terminal 2
./tests/vm-test.sh --local --delete &

# Wait for both
wait
```

## Performance Tips

1. **Use SSD storage** for VM images (much faster)
2. **Allocate more RAM** to the base VM (4-8GB recommended)
3. **Use Virtualization mode** instead of emulation
4. **Pre-install Xcode CLI tools** in base VM to save time
5. **Snapshot the base VM** after guest agent setup

## Security Considerations

- Test VMs have full network access
- Don't store sensitive data in base VM
- Test VMs may expose your GitHub credentials if using SSH
- Use throwaway credentials for testing if needed

## Future Enhancements

- [ ] Support for local file copy via shared folders
- [ ] Parallel test execution
- [ ] Snapshot-based rollback for faster re-testing
- [ ] Integration test suite (test specific features)
- [ ] Performance benchmarking
- [ ] Automated base VM creation from ISO
- [ ] Support for other VM platforms (Parallels, VMware)

## Related Documentation

- [Main Testing Guide](./TESTING.md)
- [Quick Start Testing](./QUICK_START_TESTING.md)
- [UTM Documentation](https://docs.getutm.app/)
