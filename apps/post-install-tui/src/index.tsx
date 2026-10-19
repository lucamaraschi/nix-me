import React from 'react';
import { render } from 'ink';
import { App } from './App.js';

if (process.argv.includes('--version')) {
  console.log('nix-me-tui 1.0.0');
} else {
  render(<App />);
}
