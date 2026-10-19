#!/usr/bin/env tsx
import { build } from 'esbuild';
import { chmod } from 'fs/promises';

async function bundle() {
  console.log('Building nix-me TUI...');

  await build({
    entryPoints: ['src/index.tsx'],
    bundle: true,
    platform: 'node',
    target: 'node26',
    outfile: 'dist/index.js',
    format: 'esm',
    banner: {
      js: '#!/usr/bin/env node\nimport { createRequire } from "node:module"; const require = createRequire(import.meta.url);',
    },
    external: ['fsevents'], // macOS only, optional
    minify: true,
  });

  await chmod('dist/index.js', 0o755);

  console.log('✓ Built to dist/index.js');
}

bundle().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
