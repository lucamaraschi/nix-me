import React from 'react';
import { Box, Text } from 'ink';

function BorderedBox({ children, color = 'white' }: { children: React.ReactNode; color?: string }) {
  return (
    <Box flexDirection="column" borderStyle="round" borderColor={color} padding={1}>
      {children}
    </Box>
  );
}

interface InspectorProps {
  onBack: () => void;
}

export function Inspector({ onBack }: InspectorProps) {
  return (
    <Box flexDirection="column" width={80}>
      {/* Header */}
      <Box marginBottom={1}>
        <Text bold color="cyan"> 🔍 INSPECTOR </Text>
        <Text dimColor>  Explore your system configuration</Text>
      </Box>

      {/* Inspector Menu */}
      <BorderedBox color="cyan">
        <Box flexDirection="column">
          <Text bold color="cyan">Available Inspections</Text>

          <Box marginTop={1} flexDirection="column">
            <Box marginBottom={1}>
              <Text bold color="blue">[1]</Text>
              <Text>  📊 Overview dashboard</Text>
            </Box>
            <Box marginBottom={1}>
              <Text bold color="blue">[2]</Text>
              <Text>  🍺 Installed apps (Homebrew)</Text>
            </Box>
            <Box marginBottom={1}>
              <Text bold color="blue">[3]</Text>
              <Text>  📦 System packages (Nix)</Text>
            </Box>
            <Box marginBottom={1}>
              <Text bold color="blue">[4]</Text>
              <Text>  📝 Configuration files</Text>
            </Box>
            <Box marginBottom={1}>
              <Text bold color="blue">[5]</Text>
              <Text>  📜 Recent changes (Git)</Text>
            </Box>
            <Box>
              <Text bold color="blue">[6]</Text>
              <Text>  ⬆️  Pending updates</Text>
            </Box>
          </Box>

          <Box marginTop={1} paddingTop={1} borderStyle="single" borderTop>
            <Text bold color="red">[0]</Text>
            <Text>  ← Back to dashboard</Text>
          </Box>
        </Box>
      </BorderedBox>

      <Box marginTop={1}>
        <Text dimColor>Select an option to view detailed information</Text>
      </Box>
    </Box>
  );
}
