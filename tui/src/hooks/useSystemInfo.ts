import { useState, useEffect } from 'react';
import { $ } from 'zx';
import type { SystemInfo } from '../types.js';

// Configure zx globally
$.verbose = false;
$.quiet = true;

export function useSystemInfo(): SystemInfo {
  const [info, setInfo] = useState<SystemInfo>({
    hostname: 'loading...',
    generation: 'N/A',
    branch: 'N/A',
    uncommitted: 0,
    packages: {
      guiApps: 0,
      brewCLI: 0,
      nixCLI: 0,
    },
    updates: 0,
  });

  useEffect(() => {
    async function fetchInfo() {
      try {
        // Get hostname
        let hostname = 'unknown';
        try {
          const result = await $`/bin/hostname -s`;
          hostname = result.stdout.trim().toLowerCase();
        } catch {}

        // Get generation
        let generation = 'N/A';
        try {
          const result = await $`/run/current-system/sw/bin/darwin-rebuild --list-generations 2>/dev/null || true`;
          const lines = result.stdout.trim().split('\n').filter(l => l.trim());
          if (lines.length > 0) {
            const lastLine = lines[lines.length - 1];
            generation = lastLine.split(/\s+/)[0] || 'N/A';
          }
        } catch {}

        // Detect config directory
        const home = process.env.HOME || '/Users/batman';
        const configDir = `${home}/.config/nixpkgs`;

        // Get git branch and uncommitted changes
        let branch = 'N/A';
        let uncommitted = 0;

        try {
          const branchResult = await $`/usr/bin/git -C ${configDir} branch --show-current 2>/dev/null || echo N/A`;
          branch = branchResult.stdout.trim() || 'N/A';

          const statusResult = await $`/usr/bin/git -C ${configDir} status --porcelain 2>/dev/null || true`;
          const statusLines = statusResult.stdout.trim().split('\n').filter(l => l.trim());
          uncommitted = statusLines.length;
        } catch {}

        // Get brew package counts
        let guiApps = 0;
        let brewCLI = 0;
        let updates = 0;

        try {
          const caskResult = await $`/opt/homebrew/bin/brew list --cask 2>/dev/null || true`;
          guiApps = caskResult.stdout.trim().split('\n').filter(l => l.trim()).length;

          const formulaResult = await $`/opt/homebrew/bin/brew list --formula 2>/dev/null || true`;
          brewCLI = formulaResult.stdout.trim().split('\n').filter(l => l.trim()).length;

          const outdatedResult = await $`/opt/homebrew/bin/brew outdated 2>/dev/null || true`;
          const outdatedLines = outdatedResult.stdout.trim().split('\n').filter(l => l.trim());
          updates = outdatedLines[0] === '' ? 0 : outdatedLines.length;
        } catch {}

        // Get Nix package count
        let nixCLI = 0;
        try {
          const nixBinResult = await $`/bin/ls /run/current-system/sw/bin 2>/dev/null || true`;
          nixCLI = nixBinResult.stdout.trim().split('\n').filter(l => l.trim()).length;
        } catch {}

        setInfo({
          hostname,
          generation,
          branch,
          uncommitted,
          packages: {
            guiApps,
            brewCLI,
            nixCLI,
          },
          updates,
        });
      } catch (error) {
        // Silently fail - keep showing last known state
      }
    }

    fetchInfo();
    const interval = setInterval(fetchInfo, 5000); // Refresh every 5s

    return () => clearInterval(interval);
  }, []);

  return info;
}
