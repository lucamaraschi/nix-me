#!/usr/bin/env bash
set -euo pipefail

echo "==> Resetting Raycast window placement..."

osascript -e 'tell application "Raycast" to quit' >/dev/null 2>&1 || true
defaults write com.raycast.macos raycastPreferredWindowMode -string default
defaults delete com.raycast.macos mainWindowPositionCache >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true
open -a Raycast

echo "==> Raycast window placement reset"
