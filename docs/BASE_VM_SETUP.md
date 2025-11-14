# Base VM Setup Guide

Complete guide for setting up a base macOS VM for nix-me testing.

## Quick Start (Automated) ⭐

### Prerequisites

1. Create a fresh macOS VM in UTM
2. Complete macOS installation
3. **Enable Remote Login:**
   - System Settings → General → Sharing
   - Enable "Remote Login"
   - Allow access for your user

### Automated Setup

```bash
# From your host machine (not inside the VM)
./tests/setup-base-vm-ssh.sh --vm="macOS Tahoe - base" --user=admin
```

That's it! The script will:
- ✓ Start the VM
- ✓ Install Homebrew
- ✓ Install QEMU guest agent
- ✓ Configure system settings
- ✓ Shut down the VM
- ✓ VM is ready for testing

**First run will prompt for password** (or use SSH keys for passwordless setup)

---

## Manual Setup (Inside VM)

If you prefer to set up manually or automated setup isn't working:

### 1. Inside the VM

Run this inside the VM terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/lucamaraschi/nix-me/main/tests/setup-base-vm.sh | bash
```

### 2. Shut down

```bash
sudo shutdown -h now
```

---

## Automated Setup Options

### Basic Usage

```bash
./tests/setup-base-vm-ssh.sh --vm="VM Name" --user=username
```

### Advanced Options

```bash
# Disable SSH after setup (more secure)
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --disable-ssh

# Keep VM running after setup
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --no-shutdown

# Specify IP manually (if auto-detection fails)
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --ip=192.168.64.5

# Use SSH key
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --ssh-key=~/.ssh/id_rsa
```

### All Options

| Option | Description | Default |
|--------|-------------|---------|
| `--vm=NAME` | VM name (required) | - |
| `--user=USER` | SSH username (required) | - |
| `--ip=IP` | VM IP address | Auto-detect |
| `--ssh-key=PATH` | SSH key path | Default key |
| `--disable-ssh` | Disable SSH after setup | Keep enabled |
| `--no-shutdown` | Keep VM running | Shutdown |
| `--no-start` | VM already running | Start VM |

---

## SSH Key Setup (Optional)

For passwordless setup, configure SSH keys:

### 1. Generate SSH key (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "vm-testing"
```

### 2. Copy to VM

```bash
# Replace with your VM's IP
ssh-copy-id admin@192.168.64.5
```

### 3. Test

```bash
ssh admin@192.168.64.5 "echo 'Success!'"
```

Now automated setup won't prompt for password.

---

## Creating a Base VM from Scratch

### 1. Create VM in UTM

1. Open UTM
2. Click "+" → "Virtualize"
3. Select "macOS 12+"
4. Configure:
   - **RAM**: 4GB minimum, 8GB recommended
   - **CPU**: 2 cores minimum, 4 recommended
   - **Disk**: 64GB minimum
   - **Network**: Shared Network
5. Name it (e.g., "macOS Tahoe - base")

### 2. Install macOS

1. Start the VM
2. Follow installation wizard
3. Create a user account (remember username/password)
4. Complete setup

### 3. Enable Remote Login

1. System Settings → General → Sharing
2. Turn on "Remote Login"
3. Allow access for your user

### 4. Run Automated Setup

```bash
./tests/setup-base-vm-ssh.sh --vm="macOS Tahoe - base" --user=yourusername
```

### 5. Verify

```bash
# Check guest agent is installed
/Applications/UTM.app/Contents/MacOS/utmctl ip-address "macOS Tahoe - base"
```

Should show the VM's IP address.

---

## What Gets Installed

The setup scripts install and configure:

### Software
- ✓ **Homebrew** - Package manager
- ✓ **QEMU guest agent** - For UTM communication

### System Settings
- ✓ Disable screen saver (prevents sleep during tests)
- ✓ Disable system sleep
- ✓ Disable automatic updates

### Network
- ✓ Shared network (VM can access internet)
- ✓ Host can SSH to VM

---

## Troubleshooting

### "SSH connection failed"

**Check Remote Login:**
```bash
# Inside VM
sudo systemsetup -getremotelogin
```

Should show: `Remote Login: On`

**Enable it:**
```bash
# Inside VM
sudo systemsetup -setremotelogin on
```

### "Could not detect VM IP address"

**Manual IP detection:**
```bash
# Inside VM
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Then use `--ip` flag:
```bash
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --ip=192.168.64.X
```

### "VM not found"

**List available VMs:**
```bash
/Applications/UTM.app/Contents/MacOS/utmctl list
```

Use exact name from the list.

### "Permission denied (publickey,password)"

**Options:**

1. **Use password:** SSH will prompt for password on first connection
2. **Set up SSH keys:** See "SSH Key Setup" section above
3. **Check SSH is enabled in VM:** System Settings → Sharing → Remote Login

### Homebrew installation hangs

**Inside VM, run manually:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then re-run automated setup.

---

## Multiple Base VMs

You can maintain multiple base VMs for different scenarios:

```bash
# Clean macOS only
./tests/setup-base-vm-ssh.sh --vm="macOS Clean" --user=admin

# With development tools pre-installed
./tests/setup-base-vm-ssh.sh --vm="macOS Dev Base" --user=admin

# Different macOS version
./tests/setup-base-vm-ssh.sh --vm="macOS Sonoma Base" --user=admin
```

Then use specific base VMs for testing:

```bash
./tests/vm-test.sh --base-vm="macOS Clean"
./tests/vm-test.sh --base-vm="macOS Dev Base"
```

---

## Security Considerations

### Disable SSH After Setup

```bash
./tests/setup-base-vm-ssh.sh --vm="My VM" --user=admin --disable-ssh
```

This is more secure but means you can't SSH in again without re-enabling.

### VM Isolation

Base VMs have full network access. Don't store sensitive data in them.

### Snapshots

Take a snapshot after setup for quick restore:

1. In UTM, right-click VM
2. Select "Snapshot"
3. Name it (e.g., "Clean base with guest agent")

---

## Best Practices

1. **Keep base VM minimal** - Don't install unnecessary software
2. **Take snapshots** - Before and after setup
3. **Use descriptive names** - "macOS-14.5-clean-base" instead of "base"
4. **Document special configs** - If you customize the base VM
5. **Regular updates** - Recreate base VMs periodically with latest macOS

---

## Next Steps

After base VM is set up:

1. **Verify it works:**
   ```bash
   ./tests/vm-test.sh --base-vm="Your Base VM"
   ```

2. **Create snapshots** for different test scenarios

3. **Document** any customizations you make

---

## Related Documentation

- [VM Testing Guide](./VM_TESTING.md)
- [VM Testing Quick Start](./VM_TESTING_QUICKSTART.md)
- [Main Testing Guide](./TESTING.md)
