import { useState, useEffect } from 'react';
import { $, which } from 'zx';
import type { SystemInfo } from '../types.js';

// Safe command execution with fallback
async function safeExec(cmd: string, fallback: string = ''): Promise<string> {
  try {
    $.verbose = false;
    $.shell = '/bin/bash';
    const result = await $`${[cmd]}`;
    return result.stdout.trim();
  } catch {
    return fallback;
  }
}

// Count lines in command output
async function countLines(cmd: string): Promise<number> {
  try {
    const output = await safeExec(cmd, '0');
    return parseInt(output) || 0;
  } catch {
    return 0;
  }
}

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
        // Silence zx command output
        $.verbose = false;
        $.quiet = true;

        // Set PATH to include common Nix locations
        process.env.PATH = [
          '/run/current-system/sw/bin',
          '/nix/var/nix/profiles/default/bin',
          '/usr/local/bin',
          '/opt/homebrew/bin',
          process.env.PATH,
        ].join(':');

        // Get hostname
        const hostnameResult = await $`hostname -s 2>/dev/null`.catch(() => ({ stdout: 'unknown' }));
        const hostname = hostnameResult.stdout.toString().trim().toLowerCase();

        // Get generation
        let generation = 'N/A';
        try {
          const darwinRebuild = await which('darwin-rebuild', { nothrow: true });
          if (darwinRebuild) {
            const genResult = await $`darwin-rebuild --list-generations 2>/dev/null`.catch(() => ({ stdout: '' }));
            const lines = genResult.stdout.toString().trim().split('\n');
            const lastLine = lines[lines.length - 1];
            if (lastLine) {
              generation = lastLine.split(/\s+/)[0] || 'N/A';
            }
          }
        } catch {}

        // Detect config directory
        const possibleDirs = [
          process.cwd(), // Current directory (for dev)
          process.env.HOME + '/.config/nixpkgs',
        ];

        let configDir = possibleDirs[0];
        for (const dir of possibleDirs) {
          try {
            await $`test -d ${dir}/.git 2>/dev/null`;
            configDir = dir;
            break;
          } catch {}
        }

        // Get git branch and uncommitted changes
        let branch = 'N/A';
        let uncommitted = 0;

        try {
          const branchResult = await $`git -C ${configDir} branch --show-current 2>/dev/null`.catch(() => ({ stdout: 'N/A' }));
          branch = branchResult.stdout.toString().trim() || 'N/A';

          const statusResult = await $`git -C ${configDir} status --porcelain 2>/dev/null`.catch(() => ({ stdout: '' }));
          const statusLines = statusResult.stdout.toString().trim().split('\n').filter(l => l.trim());
          uncommitted = statusLines.length;
        } catch {}

        // Get brew package counts
        let guiApps = 0;
        let brewCLI = 0;
        let updates = 0;

        try {
          const brew = await which('brew', { nothrow: true });
          if (brew) {
            const caskResult = await $`brew list --cask 2>/dev/null`.catch(() => ({ stdout: '' }));
            guiApps = caskResult.stdout.toString().trim().split('\n').filter(l => l.trim()).length;

            const formulaResult = await $`brew list --formula 2>/dev/null`.catch(() => ({ stdout: '' }));
            brewCLI = formulaResult.stdout.toString().trim().split('\n').filter(l => l.trim()).length;

            const outdatedResult = await $`brew outdated 2>/dev/null`.catch(() => ({ stdout: '' }));
            updates = outdatedResult.stdout.toString().trim().split('\n').filter(l => l.trim()).length;
          }
        } catch {}

        // Get Nix package count
        let nixCLI = 0;
        try {
          const nixBinResult = await $`ls /run/current-system/sw/bin 2>/dev/null`.catch(() => ({ stdout: '' }));
          nixCLI = nixBinResult.stdout.toString().trim().split('\n').filter(l => l.trim()).length;
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
