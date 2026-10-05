import * as fs from 'fs';
import * as path from 'path';

export function findProjectRoot(): string {
  const candidates = [process.env.NIX_ME_CONFIG_DIR, process.cwd()];
  const home = process.env.HOME;

  if (home) {
    candidates.push(path.join(home, '.config', 'nixpkgs'));
  }

  for (const candidate of candidates) {
    if (!candidate) continue;

    let current = path.resolve(candidate);
    while (true) {
      if (fs.existsSync(path.join(current, 'flake.nix'))) {
        return current;
      }

      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
  }

  throw new Error('Could not locate the nix-me checkout; set NIX_ME_CONFIG_DIR');
}
