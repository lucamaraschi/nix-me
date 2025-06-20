# Makefile for Multi-Machine Nix Configuration

# Variables - force lowercase hostname to avoid case issues
DETECTED_HOSTNAME := $(shell hostname -s | tr '[:upper:]' '[:lower:]')
HOSTNAME ?= $(DETECTED_HOSTNAME)
MACHINE_TYPE ?= $(shell if [[ "$(HOSTNAME)" == *"macbook"* || "$(HOSTNAME)" == *"mba"* ]]; then echo "macbook"; elif [[ "$(HOSTNAME)" == *"mini"* ]]; then echo "macmini"; else echo ""; fi)
MACHINE_NAME ?= "$(HOSTNAME)"
FLAKE_DIR ?= $(HOME)/.config/nixpkgs
DRY_RUN ?= 0

# Force hostname to lowercase in all commands
FINAL_HOSTNAME := $(shell echo "$(HOSTNAME)" | tr '[:upper:]' '[:lower:]')

.PHONY: switch build clean update check fmt help list-machines

# Default target
help:
	@echo "Usage: make [target] [HOSTNAME=name] [MACHINE_TYPE=type] [MACHINE_NAME=friendly-name]"
	@echo ""
	@echo "Targets:"
	@echo "  build           Build the configuration"
	@echo "  switch          Build and activate the configuration"
	@echo "  check           Run nix flake check"
	@echo "  update          Update flake inputs"
	@echo "  fmt             Format nix files with nixpkgs-fmt"
	@echo "  gc              Run garbage collection"
	@echo "  clean           Clean up old generations"
	@echo "  list-machines   List known machine configurations"
	@echo "  help            Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  HOSTNAME        Override hostname (default: $(FINAL_HOSTNAME))"
	@echo "  MACHINE_TYPE    Specify machine type (macbook or macmini) (default: auto-detected)"
	@echo "  MACHINE_NAME    Set the friendly computer name (default: $(MACHINE_NAME))"
	@echo "  FLAKE_DIR       Override flake directory (default: $(FLAKE_DIR))"
	@echo "  DRY_RUN         Set to 1 for dry run (default: 0)"
	@echo ""
	@echo "Machine Types:"
	@echo "  macbook         Laptop configuration with battery optimization, trackpad settings, etc."
	@echo "  macmini         Desktop configuration optimized for performance"
	@echo ""
	@echo "Examples:"
	@echo "  make switch"
	@echo "  make MACHINE_TYPE=macbook switch"
	@echo "  make HOSTNAME=mac-mini MACHINE_TYPE=macmini MACHINE_NAME=\"Studio Mac Mini\" switch"
	@echo "  make DRY_RUN=1 switch"

# Build the configuration
build:
	@echo "==> Building configuration for $(FINAL_HOSTNAME) ($(MACHINE_TYPE), $(MACHINE_NAME))..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] HOSTNAME=$(FINAL_HOSTNAME) MACHINE_TYPE=$(MACHINE_TYPE) MACHINE_NAME=\"$(MACHINE_NAME)\" nix build $(FLAKE_DIR)#darwinConfigurations.$(FINAL_HOSTNAME).system"
else
	@HOSTNAME=$(FINAL_HOSTNAME) MACHINE_TYPE=$(MACHINE_TYPE) MACHINE_NAME="$(MACHINE_NAME)" nix build $(FLAKE_DIR)#darwinConfigurations.$(FINAL_HOSTNAME).system
endif

# Build and activate the configuration
switch:
	@echo "==> Building and activating configuration for $(FINAL_HOSTNAME) ($(MACHINE_TYPE), $(MACHINE_NAME))..."
	@echo "==> Using hostname: $(FINAL_HOSTNAME)"
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] HOSTNAME=$(FINAL_HOSTNAME) MACHINE_TYPE=$(MACHINE_TYPE) MACHINE_NAME=\"$(MACHINE_NAME)\" darwin-rebuild switch --flake $(FLAKE_DIR)"
else
	@# Find darwin-rebuild in common locations
	@DARWIN_REBUILD=""; \
	if [ -x "/run/current-system/sw/bin/darwin-rebuild" ]; then \
		DARWIN_REBUILD="/run/current-system/sw/bin/darwin-rebuild"; \
	elif [ -x "$$HOME/.nix-profile/bin/darwin-rebuild" ]; then \
		DARWIN_REBUILD="$$HOME/.nix-profile/bin/darwin-rebuild"; \
	elif command -v darwin-rebuild >/dev/null 2>&1; then \
		DARWIN_REBUILD="darwin-rebuild"; \
	else \
		echo "Error: darwin-rebuild not found in PATH or common locations"; \
		echo "Make sure nix-darwin is installed and in your PATH"; \
		exit 1; \
	fi; \
	if [ "$(MACHINE_TYPE)" = "vm" ]; then \
		HOSTNAME="$(FINAL_HOSTNAME)" MACHINE_TYPE="$(MACHINE_TYPE)" MACHINE_NAME="$(MACHINE_NAME)" sudo env PATH="$$PATH" "$$DARWIN_REBUILD" switch --flake $(FLAKE_DIR) -I vm-fix=$(FLAKE_DIR)/vm-fix.nix; \
	else \
		HOSTNAME="$(FINAL_HOSTNAME)" MACHINE_TYPE="$(MACHINE_TYPE)" MACHINE_NAME="$(MACHINE_NAME)" sudo env PATH="$$PATH" "$$DARWIN_REBUILD" switch --flake $(FLAKE_DIR); \
	fi
endif

# Run a syntax check on the flake
check:
	@echo "==> Checking flake..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] nix flake check $(FLAKE_DIR)"
else
	@nix flake check $(FLAKE_DIR)
endif

# Update flake inputs
update:
	@echo "==> Updating flake inputs..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] nix flake update $(FLAKE_DIR)"
else
	@nix flake update $(FLAKE_DIR)
endif

# Format nix files
fmt:
	@echo "==> Formatting nix files..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] Find and format nix files"
else
	@find $(FLAKE_DIR) -name "*.nix" -exec nixpkgs-fmt {} \;
endif

# Run garbage collection
gc:
	@echo "==> Running garbage collection..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] nix-collect-garbage -d"
else
	@nix-collect-garbage -d
endif

# Clean up old generations
clean:
	@echo "==> Cleaning up old generations..."
ifeq ($(DRY_RUN), 1)
	@echo "[DRY RUN] nix-collect-garbage -d"
	@echo "[DRY RUN] sudo nix-collect-garbage -d"
else
	@nix-collect-garbage -d
	@sudo nix-collect-garbage -d
endif

# List known machine configurations
list-machines:
	@echo "==> Known machine configurations:"
	@echo "MacBook configurations:"
	@grep -E '"macbook-.*"' $(FLAKE_DIR)/flake.nix | sed 's/.*"\(.*\)".*/  \1/' || echo "  (none found)"
	@echo "Mac Mini configurations:"
	@grep -E '"mac-mini.*"' $(FLAKE_DIR)/flake.nix | sed 's/.*"\(.*\)".*/  \1/' || echo "  (none found)"
	@echo ""
	@echo "Current hostname will be: $(FINAL_HOSTNAME)"
	@echo ""
	@echo "To use a specific machine type without a predefined configuration:"
	@echo "  make MACHINE_TYPE=macbook switch"
	@echo "  make MACHINE_TYPE=macmini switch"