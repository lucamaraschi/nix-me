import React, { useState, useEffect } from 'react';
import { Box, Text, useInput, useApp } from 'ink';
import { Dashboard } from './components/Dashboard.js';
import { ConfigInspector } from './components/ConfigInspector.js';
import { VMManager } from './components/VMManager.js';
import { PackageBrowser } from './components/PackageBrowser.js';
import { useSystemInfo } from './hooks/useSystemInfo.js';

type Screen = 'dashboard' | 'inspector' | 'vms' | 'browse' | 'update' | 'apply';

export function App() {
  const { exit } = useApp();
  const [screen, setScreen] = useState<Screen>('dashboard');
  const systemInfo = useSystemInfo();

  useInput((input, key) => {
    if (screen === 'dashboard') {
      if (input === 'q') {
        exit();
      } else if (input === '1') {
        setScreen('browse');
      } else if (input === 'v') {
        setScreen('vms');
      } else if (input === 'i') {
        setScreen('inspector');
      }
    } else {
      // Back to dashboard on 'q' or '0' from any screen
      if (input === 'q' || input === '0') {
        setScreen('dashboard');
      }
    }
  });

  return (
    <Box flexDirection="column" paddingX={2} paddingY={1}>
      {screen === 'dashboard' && <Dashboard systemInfo={systemInfo} />}
      {screen === 'inspector' && <ConfigInspector onBack={() => setScreen('dashboard')} />}
      {screen === 'vms' && <VMManager onBack={() => setScreen('dashboard')} />}
      {screen === 'browse' && <PackageBrowser onBack={() => setScreen('dashboard')} />}
    </Box>
  );
}
