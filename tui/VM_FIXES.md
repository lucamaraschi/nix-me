# VM Creation Fixes

## Problem
When selecting "Create VM" → "Omarchy" in the TUI, a Terminal window was opening but staying in the background, making it appear that nothing was happening.

## Solution
Updated the AppleScript command to:
1. Open a new Terminal window
2. **Activate Terminal** to bring it to the front
3. Run the VM creation wizard script

## Changes Made

### File: `src/components/VMManager.tsx`

#### 1. **Fixed AppleScript Command**
- Added `activate` command to bring Terminal to the front
- Improved command construction and escaping
- Added detailed console logging for debugging

#### 2. **Improved User Feedback**
- Better success message explaining what's happening
- Clear instructions about what to do in the Terminal window
- Proper screen state management

#### 3. **Better Error Handling**
- Console logging at each step
- Clear error messages if Terminal fails to open
- Proper async/await handling

## How It Works Now

1. User presses `v` → VM Manager
2. User presses `1` → Create VM
3. SelectMenu appears with arrow key navigation
4. User selects "Omarchy" and presses Enter
5. TUI shows: "🚀 Creating omarchy VM... Opening interactive wizard"
6. **NEW:** Terminal window opens AND comes to the front
7. VM creation wizard runs interactively in Terminal
8. TUI shows success message with instructions
9. User completes wizard in Terminal
10. User presses any key in TUI to return to VM Manager

## Terminal Window Behavior

The Terminal window will:
- Open in a new tab/window
- Come to the front automatically
- Run the full interactive wizard with:
  - VM type selection (pre-selected for Omarchy)
  - VM name prompt
  - Resource allocation (memory, CPU, disk)
  - ISO download (automatic for Omarchy)
  - VM configuration creation
  - Optional UTM VM creation

## Testing

To test manually:
```bash
cd /Users/batman/src/lm/nix-me/tui
npm run dev
```

Then navigate: `v` → `1` → Select "Omarchy" → Enter

You should see:
1. A new Terminal window open and come to the front
2. The VM creation wizard running in that Terminal
3. Console logs in the original terminal showing the flow

## Console Logs

When working correctly, you'll see:
```
[SelectMenu] Enter pressed, calling onSelect with: omarchy
[VMManager] createVM called with type: omarchy
[VMManager] Executing AppleScript...
[VMManager] Command: tell application "Terminal" ...
[VMManager] Terminal opened successfully { stdout: 'tab 1 of window id XXX', stderr: '' }
```

## If Terminal Still Doesn't Appear

Check:
1. Terminal app has Automation permissions (System Settings → Privacy & Security → Automation)
2. No Terminal windows are hidden behind other windows
3. Check Terminal.app in the Dock - it should be active
4. Check Mission Control/Spaces - Terminal might be on another desktop

## Related Files
- `src/components/SelectMenu.tsx` - Interactive menu component
- `src/components/VMManager.tsx` - VM management and Terminal integration
- `lib/vm-manager.sh` - Bash script with VM creation wizard
