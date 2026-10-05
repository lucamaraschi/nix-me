import React from 'react';
import { Box, Text } from 'ink';
import Spinner from 'ink-spinner';

function BorderedBox({ children, color = 'white' }: { children: React.ReactNode; color?: string }) {
  return (
    <Box flexDirection="column" borderStyle="round" borderColor={color} padding={1}>
      {children}
    </Box>
  );
}

interface PackageBrowserProps {
  onBack: () => void;
}

export function PackageBrowser({ onBack }: PackageBrowserProps) {
  return (
    <Box flexDirection="column" width={80}>
      {/* Header */}
      <Box marginBottom={1}>
        <Text bold color="green"> 📦 PACKAGE BROWSER </Text>
        <Text dimColor>  Discover and install applications</Text>
      </Box>

      {/* Categories */}
      <Box marginBottom={1}>
        <BorderedBox color="green">
          <Box flexDirection="column">
            <Text bold color="green">📚 Browse Categories</Text>

            <Box marginTop={1} flexDirection="column">
              <Box marginBottom={1}>
                <Text bold color="cyan">[1]</Text>
                <Text>  💻 Development Tools</Text>
              </Box>
              <Box marginBottom={1}>
                <Text bold color="cyan">[2]</Text>
                <Text>  🎨 Creative & Design</Text>
              </Box>
              <Box marginBottom={1}>
                <Text bold color="cyan">[3]</Text>
                <Text>  🌐 Browsers & Communication</Text>
              </Box>
              <Box marginBottom={1}>
                <Text bold color="cyan">[4]</Text>
                <Text>  🔧 Utilities & System</Text>
              </Box>
              <Box>
                <Text bold color="cyan">[5]</Text>
                <Text>  🎮 Entertainment</Text>
              </Box>
            </Box>
          </Box>
        </BorderedBox>
      </Box>

      {/* Search */}
      <Box marginBottom={1}>
        <BorderedBox color="magenta">
        <Box flexDirection="column">
          <Text bold color="magenta">🔍 Search</Text>
          <Box marginTop={1}>
            <Text bold color="yellow">[s]</Text>
            <Text>  Search for packages by name</Text>
          </Box>
        </Box>
      </BorderedBox>
      </Box>

      {/* Loading indicator */}
      <Box marginBottom={1}>
        <Text color="cyan">
          <Spinner type="dots" />
        </Text>
        <Text dimColor>  Loading package database...</Text>
      </Box>

      {/* Back button */}
      <BorderedBox color="red">
        <Box>
          <Text bold color="red">[0]</Text>
          <Text>  ← Back to dashboard</Text>
        </Box>
      </BorderedBox>

      <Box marginTop={1}>
        <Text dimColor>Use arrow keys to navigate • Enter to install</Text>
      </Box>
    </Box>
  );
}
