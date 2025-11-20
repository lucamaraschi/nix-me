import React from 'react';
import { Box, Text } from 'ink';
import type { SystemInfo } from '../types.js';

// Simple bordered box component
function BorderedBox({ children, color = 'white', title }: { children: React.ReactNode; color?: string; title?: string }) {
  return (
    <Box flexDirection="column" borderStyle="round" borderColor={color} padding={1}>
      {title && <Text bold color={color}>{title}</Text>}
      {children}
    </Box>
  );
}

interface DashboardProps {
  systemInfo: SystemInfo;
}

export function Dashboard({ systemInfo }: DashboardProps) {
  const { hostname, generation, branch, uncommitted, packages, updates } = systemInfo;

  const totalPackages = packages.guiApps + packages.brewCLI + packages.nixCLI;
  const statusColor = uncommitted > 0 ? 'yellow' : 'green';
  const statusIcon = uncommitted > 0 ? '⚠' : '✓';

  return (
    <Box flexDirection="column" width="100%">
      {/* Logo & Header */}
      <Box marginBottom={1} flexDirection="column" alignItems="center">
        <Text bold color="cyan">
          ╔═══════════════════════════════════════════════════════════╗
        </Text>
        <Text bold color="cyan">
          ║                                                           ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">███╗   ██╗██╗██╗  ██╗</Text>     <Text color="cyan">███╗   ███╗███████╗</Text>  ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">████╗  ██║██║╚██╗██╔╝</Text>     <Text color="cyan">████╗ ████║██╔════╝</Text>  ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">██╔██╗ ██║██║ ╚███╔╝ </Text>     <Text color="cyan">██╔████╔██║█████╗  </Text>  ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">██║╚██╗██║██║ ██╔██╗ </Text>     <Text color="cyan">██║╚██╔╝██║██╔══╝  </Text>  ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">██║ ╚████║██║██╔╝ ██╗</Text>     <Text color="cyan">██║ ╚═╝ ██║███████╗</Text>  ║
        </Text>
        <Text bold>
          ║  <Text color="magenta">╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝</Text>     <Text color="cyan">╚═╝     ╚═╝╚══════╝</Text>  ║
        </Text>
        <Text bold color="cyan">
          ║                                                           ║
        </Text>
        <Text dimColor>
          ║          Interactive Configuration Manager                ║
        </Text>
        <Text bold color="cyan">
          ╚═══════════════════════════════════════════════════════════╝
        </Text>
      </Box>

      {/* Row 1: System Status - Full Width */}
      <Box width="100%" height={10} marginBottom={1}>
        <BorderedBox color="cyan">
          <Box flexDirection="column" height="100%">
            <Text bold color="cyan">⚙️  SYSTEM STATUS</Text>
            <Box marginTop={1}>
              <Box width="50%">
                <Box flexDirection="column">
                  <Box><Text dimColor>Hostname   : </Text><Text bold color="white">{hostname}</Text></Box>
                  <Box><Text dimColor>Generation : </Text><Text bold color="magenta">{generation}</Text></Box>
                  <Box><Text dimColor>Branch     : </Text><Text bold color="blue">{branch}</Text></Box>
                </Box>
              </Box>
              <Box width="50%">
                <Box flexDirection="column">
                  <Box><Text dimColor>Total Packages : </Text><Text bold color="white">{totalPackages}</Text></Box>
                  <Box><Text dimColor>Updates Avail  : </Text><Text bold color={updates > 0 ? "yellow" : "green"}>{updates}</Text></Box>
                  <Box marginTop={1}>
                    <Text color={statusColor} bold>{statusIcon} </Text>
                    {uncommitted > 0 ? (
                      <Text color="yellow">{uncommitted} uncommitted change{uncommitted > 1 ? 's' : ''}</Text>
                    ) : (
                      <Text color="green">Clean working tree</Text>
                    )}
                  </Box>
                </Box>
              </Box>
            </Box>
          </Box>
        </BorderedBox>
      </Box>

      {/* Row 2: Package Stats - Three Columns Spanning Full Width */}
      <Box width="100%" height={7} marginBottom={1}>
        <BorderedBox color="green">
          <Box flexDirection="column" height="100%">
            <Text bold color="green">📦 PACKAGES</Text>
            <Box marginTop={1}>
              <Box width="33.33%">
                <Box flexDirection="column">
                  <Text bold color="cyan">📱 GUI Applications</Text>
                  <Box marginTop={1}>
                    <Text bold color="cyan" fontSize={18}>{packages.guiApps} </Text>
                    <Text dimColor>installed apps</Text>
                  </Box>
                </Box>
              </Box>
              <Box width="33.33%">
                <Box flexDirection="column">
                  <Text bold color="magenta">🔧 Brew CLI Tools</Text>
                  <Box marginTop={1}>
                    <Text bold color="magenta" fontSize={18}>{packages.brewCLI} </Text>
                    <Text dimColor>command-line tools</Text>
                  </Box>
                </Box>
              </Box>
              <Box width="33.34%">
                <Box flexDirection="column">
                  <Text bold color="blue">📦 Nix Packages</Text>
                  <Box marginTop={1}>
                    <Text bold color="blue" fontSize={18}>{packages.nixCLI} </Text>
                    <Text dimColor>system packages</Text>
                  </Box>
                </Box>
              </Box>
            </Box>
          </Box>
        </BorderedBox>
      </Box>

      {/* Row 3: Quick Actions - Full Width with Descriptions */}
      <Box width="100%" height={16} marginBottom={1}>
        <BorderedBox color="yellow">
          <Box flexDirection="column" height="100%">
            <Box>
              <Text bold color="yellow">⚡  QUICK ACTIONS</Text>
              <Box flexGrow={1}></Box>
            </Box>
            <Box marginTop={1} flexDirection="column">
              <Box>
                <Text bold color="cyan">[1]</Text>
                <Text> Browse Packages  </Text>
                <Text dimColor>- Discover and install new applications</Text>
              </Box>
              <Box marginTop={1}>
                <Text bold color="green">[2]</Text>
                <Text> Update All       </Text>
                <Text dimColor>- Update all outdated packages</Text>
              </Box>
              <Box marginTop={1}>
                <Text bold color="magenta">[3]</Text>
                <Text> Apply Changes    </Text>
                <Text dimColor>- Rebuild system with new configuration</Text>
              </Box>
              <Box marginTop={1}>
                <Text bold color="blue">[v]</Text>
                <Text> Virtual Machines </Text>
                <Text dimColor>- Create test VM (100% automated)</Text>
              </Box>
              <Box marginTop={1}>
                <Text bold color="blue">[i]</Text>
                <Text> Inspector        </Text>
                <Text dimColor>- View detailed package and config info</Text>
              </Box>
              <Box marginTop={1}>
                <Text bold color="red">[q]</Text>
                <Text> Quit             </Text>
                <Text dimColor>- Exit nix-me</Text>
              </Box>
            </Box>
            <Box>
              <Box width="50%"></Box>
              <Box width="50%"></Box>
            </Box>
          </Box>
        </BorderedBox>
      </Box>

      <Box justifyContent="center">
        <Text dimColor>Auto-refresh: 5s • Press any key to navigate</Text>
      </Box>
    </Box>
  );
}
