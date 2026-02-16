# Temporarily Removed Apps

Apps removed from nix-me config due to issues, with manual installation instructions.

---

## Metasploit

**Removed from:** `hosts/profiles/hacking.nix`
**Reason:** Deprecated by Homebrew (doesn't pass macOS Gatekeeper). Will be disabled on 2026-09-01.
**Date removed:** 2025-02-13

### Manual Installation Options

#### Option 1: Official Installer (Recommended)
```bash
# Download from Rapid7
curl -o /tmp/metasploit.pkg https://downloads.metasploit.com/data/releases/metasploit-latest-osx-installer.pkg

# Install (requires admin password)
sudo installer -pkg /tmp/metasploit.pkg -target /

# Verify installation
/opt/metasploit-framework/bin/msfconsole --version
```

#### Option 2: Docker
```bash
# Pull the official image
docker pull metasploitframework/metasploit-framework

# Run interactively
docker run -it metasploitframework/metasploit-framework

# Or with persistent data
docker run -it -v ~/.msf4:/root/.msf4 metasploitframework/metasploit-framework
```

#### Option 3: Homebrew (until Sept 2026)
```bash
# Still works but shows deprecation warning
brew install --cask metasploit
```

### Post-Installation

Initialize the database:
```bash
msfdb init
```

The `MSF_DATABASE_CONFIG` environment variable is still set in the hacking profile pointing to `~/.msf4/database.yml`.

---

*Add new entries above this line*
