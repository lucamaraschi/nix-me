# nix-me TUI

Beautiful terminal UI for nix-me, built with [Ink](https://github.com/vadimdemedes/ink).

## Development

```bash
# Install dependencies
npm install

# Run in dev mode
npm run dev

# Build bundled version
npm run bundle

# Watch mode (auto-reload)
npm run watch
```

## Features

- **Dashboard** - Live system stats, package counts, updates
- **Inspector** - Explore installed packages and configurations
- **VM Manager** - Create and manage VMs (test-macos, Omarchy)
- **Package Browser** - Browse and install apps interactively
- **Auto-refresh** - Stats update every 5 seconds

## Stack

- **Ink** - React for CLIs
- **TypeScript** - Type safety
- **zx** - Shell command execution
- **esbuild** - Fast bundling

## Usage

After building:

```bash
./dist/index.js
```

Or from nix-me:

```bash
nix-me  # Uses TUI if available
```
