# VM Testing Quick Start

Quick guide to get started with automated VM testing.

## 5-Minute Setup

### 1. Install UTM

```bash
brew install --cask utm
```

### 2. Create Base VM

1. Open UTM
2. Create new VM:
   - Type: **Virtualize** (macOS 12+)
   - OS: **macOS**
   - RAM: **4GB** minimum
   - CPU: **2 cores** minimum
   - Disk: **64GB** minimum

3. Install macOS and complete setup wizard

4. Inside the VM, run:

```bash
# Copy the setup script to VM (manually or via download)
curl -fsSL https://raw.githubusercontent.com/lucamaraschi/nix-me/main/tests/setup-base-vm.sh -o setup-base-vm.sh
chmod +x setup-base-vm.sh
./setup-base-vm.sh
```

5. Shut down the VM:

```bash
sudo shutdown -h now
```

6. Rename VM in UTM to: `macOS Tahoe - base`

### 3. Run Tests

```bash
cd /path/to/nix-me
./tests/vm-test.sh
```

That's it! The script will:
- Clone the base VM (default: "macOS Tahoe - base")
- Create a test VM with random name
- Install nix-me
- Run tests
- Ask if you want to keep or delete the test VM

**If your base VM has a different name:**

```bash
./tests/vm-test.sh --base-vm="Your VM Name"
```

## Usage Examples

### Test Latest Release

```bash
./tests/vm-test.sh
```

### Test Local Changes

```bash
./tests/vm-test.sh --source=local
```

### Cleanup Control

```bash
# Delete on success, keep on failure (recommended for development)
./tests/vm-test.sh --onsuccess=delete --onfailure=keep

# Always keep for inspection
./tests/vm-test.sh --onsuccess=keep --onfailure=keep

# Always delete (good for CI)
./tests/vm-test.sh --onsuccess=delete --onfailure=delete
```

### Combined Examples

```bash
# Test local changes, auto-delete if successful
./tests/vm-test.sh --source=local --onsuccess=delete

# Test with verbose output, keep on failure
./tests/vm-test.sh --verbose --onfailure=keep
```

### Legacy Flags (Still Supported)

```bash
./tests/vm-test.sh --local    # Same as --source=local
./tests/vm-test.sh --keep     # Keep regardless of result
./tests/vm-test.sh --delete   # Delete regardless of result
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

### "VM did not become ready"

Ensure QEMU guest agent is installed:

```bash
# Inside the VM
brew install qemu
brew services start qemu
```

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
