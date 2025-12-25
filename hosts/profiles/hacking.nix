# Hacking/Security testing profile
# Adds penetration testing, network security, and ethical hacking tools
# WARNING: These tools should only be used for authorized security testing
{ config, pkgs, lib, ... }:

{
  apps = {
    useBaseLists = true;

    # Security/Hacking GUI applications
    casksToAdd = [
      # Network analysis
      "wireshark-app"       # Network protocol analyzer
      "zenmap"              # Nmap GUI

      # Reverse engineering
      "hopper-disassembler" # macOS/iOS disassembler

      # Virtualization for testing
      "utm"                 # VMs for isolated testing

      # Exploitation
      "metasploit"          # Penetration testing framework
    ];

    # Security CLI tools via Homebrew
    brewsToAdd = [
      # WiFi security (AirJack dependencies)
      "hashcat"             # Password recovery
      "hcxtools"            # Handshake capture tools
      "libpcap"             # Packet capture library
      "wget"                # HTTP retrieval

      # Network scanning & enumeration
      "masscan"             # Fast port scanner
      "nikto"               # Web server scanner

      # Password & hash tools
      "john"                # John the Ripper
      "hydra"               # Brute force tool

      # Exploitation
      "sqlmap"              # SQL injection tool

      # Wireless
      "aircrack-ng"         # WiFi security auditing

      # Reverse engineering
      "ghidra"              # NSA reverse engineering tool
    ];

    # Security packages via Nix
    systemPackagesToAdd = [
      # Network tools
      "nmap"
      "netcat"
      "socat"
      "tcpdump"
      "mitmproxy"

      # Reconnaissance
      "whois"
      "dnsutils"            # dig, nslookup

      # Binary analysis
      "binutils"
      "radare2"

      # Cryptography
      "openssl"
      "gnupg"

      # Scripting
      "python3"

      # Custom packages (from overlays)
      "airjack"             # WiFi security testing tool
      "airjack-update"      # Update AirJack to latest version
    ];
  };

  # Security-specific environment
  environment.variables = {
    # Metasploit database
    MSF_DATABASE_CONFIG = "$HOME/.msf4/database.yml";
  };

  # Security-focused system preferences (use mkDefault so other profiles can override)
  system.defaults = {
    screensaver = {
      askForPassword = lib.mkDefault true;
      askForPasswordDelay = lib.mkDefault 0;  # Immediate lock
    };
  };
}
