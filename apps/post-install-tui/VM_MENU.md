# Interactive VM Menu

## New Features

### SelectMenu Component
A reusable, Claude-style interactive menu component with:
- **Arrow key navigation** (↑↓ or j/k)
- **Enter to select**
- **ESC/q to cancel**
- Beautiful bordered UI matching the nix-me design

### VM Manager Integration
The VM Manager now includes:

1. **Interactive VM Type Selection**
   - Navigate with arrow keys
   - Choose between test-macos and Omarchy VMs
   - Visual feedback with colors and descriptions

2. **List VMs**
   - Shows all UTM virtual machines
   - Press any key to return

3. **Create VM**
   - Opens interactive wizard in new Terminal window
   - Walks through VM creation step-by-step
   - Integrates with existing bash VM management scripts

## Usage

From the dashboard:
1. Press `v` to enter VM Manager
2. Press `1` to create a new VM
3. Use arrow keys to select VM type
4. Press Enter to start the creation wizard

The wizard will open in a new Terminal window with the full interactive experience, including resource allocation, ISO download, and configuration.

## Design Philosophy

- Maintains the current visual design language
- Matches Claude's option picker UX
- Keyboard-driven for efficiency
- Clear visual feedback and prompts
