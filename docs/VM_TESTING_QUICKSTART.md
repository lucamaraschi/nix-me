# VM Testing Quick Start

Quick guide to get started with automated VM testing.

## 5-Minute Setup

### 1. Install UTM

```bash
brew install --cask utm
```

### 2. Create Base VM

**Quick Way (Automated):**

1. Create new VM in UTM:
   - Type: **Virtualize** (macOS 12+)
   - RAM: **4GB** minimum
   - CPU: **2 cores** minimum
   - Disk: **64GB** minimum

2. Install macOS and complete setup wizard

3. **Enable Remote Login** in VM:
   System Settings → General → Sharing → Remote Login

4. **From your host machine**, run:

```bash
./tests/setup-base-vm-ssh.sh --vm="macOS Tahoe - base" --user=admin
```

**Done!** The script handles everything automatically.

**Manual Way:**

Follow steps in [Base VM Setup Guide](./BASE_VM_SETUP.md)

### 3. Run Tests

```bash
cd /path/to/nix-me
./tests/vm-test.sh --vm-user=admin
```

**Note:** Replace `admin` with the username in your base VM.

That's it! The script will:
- Clone the base VM (default: "macOS Tahoe - base")
- Create a test VM with random name
- Connect via SSH and install nix-me (including Homebrew)
- Run tests
- Ask if you want to keep or delete the test VM

**If your base VM has a different name:**

```bash
./tests/vm-test.sh --vm-user=admin --base-vm="Your VM Name"
```

## Usage Examples

### Test Latest Release

```bash
./tests/vm-test.sh --vm-user=admin
```

### Test Local Changes

```bash
./tests/vm-test.sh --vm-user=admin --source=local
```

### Cleanup Control

```bash
# Delete on success, keep on failure (recommended for development)
./tests/vm-test.sh --vm-user=admin --onsuccess=delete --onfailure=keep

# Always keep for inspection
./tests/vm-test.sh --vm-user=admin --onsuccess=keep --onfailure=keep

# Always delete (good for CI)
./tests/vm-test.sh --vm-user=admin --onsuccess=delete --onfailure=delete
```

### Combined Examples

```bash
# Test local changes, auto-delete if successful
./tests/vm-test.sh --vm-user=admin --source=local --onsuccess=delete

# Test with verbose output, keep on failure
./tests/vm-test.sh --vm-user=admin --verbose --onfailure=keep
```

### Legacy Flags (Still Supported)

```bash
./tests/vm-test.sh --vm-user=admin --local    # Same as --source=local
./tests/vm-test.sh --vm-user=admin --keep     # Keep regardless of result
./tests/vm-test.sh --vm-user=admin --delete   # Delete regardless of result
```

## What Gets Tested

1. ✓ Nix installation
2. ✓ darwin-rebuild availability
3. ✓ Configuration directory creation
4. ✓ Flake configuration
5. ✓ nix-me CLI availability

## Troubleshooting

### "Base VM not found"

Make sure your VM is named exactly: `macOS Tahoe - base`

Or edit `tests/vm-test.sh` and change:

```bash
BASE_VM_NAME="Your VM Name Here"
```

### "Could not connect via SSH"

Ensure Remote Login is enabled in your base VM:

```bash
# Inside the VM (or via System Settings)
sudo systemsetup -setremotelogin on

# Verify it's enabled
sudo systemsetup -getremotelogin
# Should show: Remote Login: On
```

Or use System Settings → General → Sharing → Remote Login

### Installation Times Out

First installation can take 30+ minutes. To increase timeout:

```bash
# Edit tests/vm-test.sh
INSTALL_TIMEOUT=3600  # 60 minutes
```

## Next Steps

- [Full VM Testing Documentation](./VM_TESTING.md)
- [Component Testing Guide](./TESTING.md)
- [Quick Start Testing](./QUICK_START_TESTING.md)
