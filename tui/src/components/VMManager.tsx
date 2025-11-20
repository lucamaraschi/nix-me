import React, { useState, useEffect } from 'react';
import { Box, Text, useInput } from 'ink';
import { SelectMenu, MenuItem } from './SelectMenu.js';
import { TextInput } from './TextInput.js';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

function BorderedBox({ children, color = 'white' }: { children: React.ReactNode; color?: string }) {
  return (
    <Box flexDirection="column" borderStyle="round" borderColor={color} padding={1}>
      {children}
    </Box>
  );
}

type VMScreen =
  | 'main'
  | 'create-select-type'
  | 'create-enter-name'
  | 'create-configure-resources'
  | 'create-confirm'
  | 'create-executing'
  | 'create-complete'
  | 'list';

interface VMConfig {
  type: string;
  name: string;
  memory: string;
  cpus: string;
  diskSize: string;
}

interface VMManagerProps {
  onBack: () => void;
}

export function VMManager({ onBack }: VMManagerProps) {
  const [screen, setScreen] = useState<VMScreen>('main');
  const [vmConfig, setVMConfig] = useState<Partial<VMConfig>>({});
  const [output, setOutput] = useState<string>('');
  const [currentStep, setCurrentStep] = useState(1);


  // All useInput hooks must be at the top, before any conditional returns
  useInput((input) => {
    if (screen === 'main') {
      if (input === '0' || input === 'q') {
        onBack();
      } else if (input === '1') {
        setScreen('create-select-type');
        setCurrentStep(1);
      } else if (input === '2') {
        listVMs();
      }
    } else if (screen === 'list' || screen === 'create-complete') {
      setScreen('main');
    } else if (screen === 'create-confirm') {
      if (input === 'y' || input === 'Y') {
        executeVMCreation();
      } else if (input === 'n' || input === 'N' || input === '0') {
        setScreen('main');
      }
    }
  });

  const listVMs = async () => {
    setScreen('list');
    setOutput('Loading VMs...');
    try {
      const { stdout } = await execAsync('/Applications/UTM.app/Contents/MacOS/utmctl list');
      setOutput(stdout || 'No VMs found');
    } catch (error: any) {
      setOutput(`Error listing VMs: ${error.message}`);
    }
  };

  const getDefaultVMName = (type: string) => {
    const date = new Date().toISOString().split('T')[0].replace(/-/g, '');
    return `${type}-${date}`;
  };

  const getSystemResources = () => {
    // Default values - in production you'd get these from sysctl
    return {
      memory: '8192',
      cpus: '4',
      diskSize: '80G'
    };
  };

  const renderProgressBar = (percent: number, width: number = 40) => {
    const filled = Math.floor((percent / 100) * width);
    const empty = width - filled;
    const bar = '█'.repeat(filled) + '░'.repeat(empty);
    return `[${bar}] ${percent}%`;
  };

  const executeVMCreation = async () => {
    setScreen('create-executing');
    setOutput('🚀 Creating VM...\n\nPreparing configuration...');

    try {
      const { type, name, memory, cpus, diskSize } = vmConfig;

      // Build the creation command
      const scriptPath = '/Users/batman/src/lm/nix-me/lib/vm-manager.sh';

      if (type === 'test-macos') {
        setOutput(`🚀 Creating test-macos VM: ${name}\n\n✓ Memory: ${memory}MB\n✓ CPUs: ${cpus}\n✓ Disk: ${diskSize}\n\nProgress:\n${renderProgressBar(10)}\n\n[1/4] Looking for base VM...`);

        try {
          // Check if base VM exists
          const baseVMPath = `${process.env.HOME}/Library/Containers/com.utmapp.UTM/Data/Documents/macOS-base.utm`;
          const { stdout: baseExists } = await execAsync(`test -d "${baseVMPath}" && echo "exists" || echo "missing"`);

          if (baseExists.trim() === 'missing') {
            setOutput((prev) => prev + '\n\n❌ Base VM not found!\n\nThe base VM "macOS-base" is required to create test VMs.\n\nPlease create the base VM first using:\n  nix-me vm create-base');
            setTimeout(() => setScreen('create-complete'), 100);
            return;
          }

          setOutput((prev) => {
            const lines = prev.split('\n');
            const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
            if (progressIndex !== -1) {
              lines[progressIndex] = renderProgressBar(25);
            }
            return lines.join('\n').replace('[1/4] Looking for base VM...', '[1/4] ✓ Base VM found');
          });

          setOutput((prev) => prev + '\n\n[2/4] Cloning base VM...');

          // Clone the base VM using utmctl
          await execAsync(`/Applications/UTM.app/Contents/MacOS/utmctl clone "macOS-base" --name "${name}"`);

          setOutput((prev) => {
            const lines = prev.split('\n');
            const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
            if (progressIndex !== -1) {
              lines[progressIndex] = renderProgressBar(70);
            }
            return lines.join('\n').replace('[2/4] Cloning base VM...', '[2/4] ✓ VM cloned successfully');
          });

          setOutput((prev) => prev + '\n\n[3/4] Opening UTM...');

          // Open UTM
          await execAsync('open -a UTM');
          await new Promise(resolve => setTimeout(resolve, 3000));

          setOutput((prev) => {
            const lines = prev.split('\n');
            const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
            if (progressIndex !== -1) {
              lines[progressIndex] = renderProgressBar(85);
            }
            return lines.join('\n').replace('[3/4] Opening UTM...', '[3/4] ✓ UTM opened');
          });

          setOutput((prev) => prev + '\n\n[4/4] Starting VM...');

          // Start the VM
          await new Promise(resolve => setTimeout(resolve, 2000));
          await execAsync(`/Applications/UTM.app/Contents/MacOS/utmctl start "${name}"`);

          setOutput((prev) => {
            const lines = prev.split('\n');
            const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
            if (progressIndex !== -1) {
              lines[progressIndex] = renderProgressBar(100);
            }
            return lines.join('\n').replace('[4/4] Starting VM...', '[4/4] ✓ VM started!');
          });

          setOutput((prev) => prev + '\n\n✅ Test VM created and started successfully!\n\n🎉 Your test environment is ready!\n\nThe VM is now running and you can test your nix-me\nconfiguration in a safe, isolated environment.\n\nWhen done testing, you can delete this VM from UTM.');

          setTimeout(() => setScreen('create-complete'), 100);
          return;

        } catch (error: any) {
          setOutput((prev) => prev + `\n\n❌ Error creating test VM:\n\n${error.message}`);
          setTimeout(() => setScreen('create-complete'), 3000);
          return;
        }
      }

      // For Omarchy, create the VM configuration
      setOutput(`🚀 Creating ${type} VM: ${name}\n\n✓ Type: ${type}\n✓ Memory: ${memory}MB\n✓ CPUs: ${cpus}\n✓ Disk: ${diskSize}\n\nProgress:\n${renderProgressBar(10)}\n\n[1/5] Generating VM configuration...`);

      // Create VM config directory
      const vmDataDir = `${process.env.HOME}/.local/share/nix-me/vms`;
      await execAsync(`mkdir -p ${vmDataDir}/configs/${name}`);

      setOutput((prev) => prev.split('\n').slice(0, -1).join('\n') + '\n[1/5] ✓ Configuration directory created\n\nProgress:\n' + renderProgressBar(20) + '\n\n[2/5] Checking ISO cache...');

      // Download ISO if needed
      if (type === 'omarchy') {
        const isoPath = `${vmDataDir}/isos/omarchy-3.1.iso`;

        // Create ISOs directory
        await execAsync(`mkdir -p ${vmDataDir}/isos`);

        // Check if ISO exists
        const { stdout: isoCheck } = await execAsync(`test -f ${isoPath} && echo "exists" || echo "missing"`);

        if (isoCheck.trim() === 'missing') {
          setOutput((prev) => prev.split('\n').slice(0, -1).join('\n') + '\n[2/5] ISO not found in cache\n\nProgress:\n' + renderProgressBar(25) + '\n\n[3/5] Downloading Omarchy ISO...');

          try {
            const isoUrl = 'https://github.com/basecamp/omakub/releases/download/v3.1/omarchy-3.1.iso';

            setOutput((prev) => prev.split('\n').slice(0, -1).join('\n') + '\n[3/5] Downloading from GitHub...\n\n' + renderProgressBar(30));

            // Download with curl and show progress
            const curlCommand = `curl -L -o "${isoPath}.tmp" "${isoUrl}" 2>&1`;

            let lastPercent = 30;
            const downloadProcess = exec(curlCommand);

            downloadProcess.stderr?.on('data', (data: Buffer) => {
              const output = data.toString();
              // Parse curl progress output
              const match = output.match(/(\d+)%/);
              if (match) {
                const percent = parseInt(match[1]);
                const overallPercent = 30 + Math.floor(percent * 0.4); // 30-70% range
                if (overallPercent > lastPercent) {
                  lastPercent = overallPercent;
                  setOutput((prev) => {
                    const lines = prev.split('\n');
                    // Find and update the progress bar line
                    const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
                    if (progressIndex !== -1) {
                      lines[progressIndex] = renderProgressBar(overallPercent);
                    }
                    return lines.join('\n');
                  });
                }
              }
            });

            await new Promise<void>((resolve, reject) => {
              downloadProcess.on('exit', (code) => {
                if (code === 0) resolve();
                else reject(new Error(`Download failed with code ${code}`));
              });
              downloadProcess.on('error', reject);
            });

            // Move temp file to final location
            await execAsync(`mv "${isoPath}.tmp" "${isoPath}"`);

            setOutput((prev) => {
              const lines = prev.split('\n');
              const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
              if (progressIndex !== -1) {
                lines[progressIndex] = renderProgressBar(70);
              }
              return lines.join('\n') + '\n✓ ISO downloaded and cached successfully!';
            });

          } catch (error: any) {
            // Fallback to browser download
            setOutput((prev) => prev.split('\n').slice(0, -1).join('\n') + '\n[3/5] Direct download failed, opening browser...\n\n' + renderProgressBar(30));

            await execAsync('open https://omarchy.org/');

            setOutput((prev) => prev + '\n\n   Browser opened - please download the ISO\n   Watching Downloads folder...');

            // Watch Downloads folder for the ISO file
            const downloadsPath = `${process.env.HOME}/Downloads`;
            let attempts = 0;
            const maxAttempts = 60; // Wait up to 5 minutes

            while (attempts < maxAttempts) {
              const { stdout: found } = await execAsync(
                `find "${downloadsPath}" -name "omarchy-3.1.iso" -or -name "omarchy*.iso" 2>/dev/null | head -1`,
                { timeout: 5000 }
              );

              if (found.trim()) {
                const downloadedFile = found.trim();
                const waitPercent = 30 + Math.floor((attempts / maxAttempts) * 40);
                setOutput((prev) => {
                  const lines = prev.split('\n');
                  const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
                  if (progressIndex !== -1) {
                    lines[progressIndex] = renderProgressBar(70);
                  }
                  return lines.join('\n') + '\n\n✓ ISO found in Downloads!\n   Moving to cache...';
                });

                await execAsync(`mv "${downloadedFile}" "${isoPath}"`);
                setOutput((prev) => prev + '\n   ✓ ISO cached successfully!');
                break;
              }

              attempts++;
              const waitPercent = 30 + Math.floor((attempts / maxAttempts) * 40);
              if (attempts % 6 === 0) {
                setOutput((prev) => {
                  const lines = prev.split('\n');
                  const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
                  if (progressIndex !== -1) {
                    lines[progressIndex] = renderProgressBar(waitPercent);
                  }
                  return lines.join('\n') + `\n   Waiting... (${Math.floor(attempts / 6)}min)`;
                });
              }
              await new Promise(resolve => setTimeout(resolve, 5000));
            }

            if (attempts >= maxAttempts) {
              setOutput((prev) => prev + '\n\n⏱️  Download timeout\n\nPlease complete manually:\n1. Download ISO from https://omarchy.org/\n2. Move to: ' + isoPath + '\n3. Run wizard again');
              setTimeout(() => setScreen('create-complete'), 100);
              return;
            }
          }
        } else {
          setOutput((prev) => prev.split('\n').slice(0, -1).join('\n') + '\n[2/5] ✓ ISO found in cache\n\nProgress:\n' + renderProgressBar(70));
        }
      }

      setOutput((prev) => prev + '\n\n[4/5] Creating VM in UTM...');

      // Convert disk size from "80G" to "80"
      const diskSizeNum = diskSize?.replace(/[^0-9]/g, '') || '80';

      // Create the UTM VM using our script
      const createVMScript = '/Users/batman/src/lm/nix-me/lib/create-utm-vm.sh';
      const isoPath = `${vmDataDir}/isos/omarchy-3.1.iso`;

      setOutput((prev) => {
        const lines = prev.split('\n');
        const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
        if (progressIndex !== -1) {
          lines[progressIndex] = renderProgressBar(75);
        }
        return lines.join('\n') + '\n   • Generating VM configuration...';
      });

      try {
        const { stdout: createOutput } = await execAsync(
          `bash "${createVMScript}" "${name}" "${memory}" "${cpus}" "${diskSizeNum}" "${isoPath}"`
        );

        setOutput((prev) => {
          const lines = prev.split('\n');
          const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
          if (progressIndex !== -1) {
            lines[progressIndex] = renderProgressBar(85);
          }
          return lines.join('\n') + '\n   • Creating disk image...';
        });

        await new Promise(resolve => setTimeout(resolve, 500));

        setOutput((prev) => {
          const lines = prev.split('\n');
          const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
          if (progressIndex !== -1) {
            lines[progressIndex] = renderProgressBar(95);
          }
          return lines.join('\n').replace('[4/5] Creating VM in UTM...', '[4/5] ✓ VM created in UTM');
        });

      } catch (error: any) {
        setOutput((prev) => prev + `\n\n⚠️  Failed to create VM automatically: ${error.message}\n\nManual creation required - see instructions below.`);
      }

      setOutput((prev) => prev + '\n\n[5/5] Starting VM...');

      setOutput((prev) => {
        const lines = prev.split('\n');
        const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
        if (progressIndex !== -1) {
          lines[progressIndex] = renderProgressBar(98);
        }
        return lines.join('\n') + '\n   • Opening UTM...';
      });

      // Open the VM directly in UTM
      const utmDir = `${process.env.HOME}/Library/Containers/com.utmapp.UTM/Data/Documents`;
      const vmPath = `${utmDir}/${name}.utm`;

      setOutput((prev) => {
        const lines = prev.split('\n');
        const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
        if (progressIndex !== -1) {
          lines[progressIndex] = renderProgressBar(99);
        }
        return lines.join('\n') + '\n   • Opening VM in UTM...';
      });

      // Open the VM file directly - this will launch UTM and import/open the VM
      try {
        await execAsync(`open "${vmPath}"`);

        // Wait for UTM to open and load the VM
        await new Promise(resolve => setTimeout(resolve, 3000));

        setOutput((prev) => {
          const lines = prev.split('\n');
          const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
          if (progressIndex !== -1) {
            lines[progressIndex] = renderProgressBar(100);
          }
          return lines.join('\n').replace('[5/5] Starting VM...', '[5/5] ✓ VM opened in UTM!');
        });

        // Try to start it via utmctl
        try {
          await new Promise(resolve => setTimeout(resolve, 2000)); // Give UTM more time to register the VM
          await execAsync(`/Applications/UTM.app/Contents/MacOS/utmctl start "${name}"`);
          setOutput((prev) => prev + '\n\n✅ VM created and started successfully!\n\n🎉 Installation is now running!\n\nThe Omarchy installer is booting in UTM.\nFollow the on-screen prompts to complete installation.');
        } catch (startError) {
          // If auto-start fails, that's okay - UTM is open with the VM ready
          setOutput((prev) => prev + '\n\n✅ VM created and opened in UTM!\n\n🎉 Your VM is ready!\n\nUTM has opened with your new VM.\nClick the ▶️ play button to start the installation.');
        }

      } catch (error: any) {
        setOutput((prev) => {
          const lines = prev.split('\n');
          const progressIndex = lines.findIndex(line => line.includes('[█') || line.includes('[░'));
          if (progressIndex !== -1) {
            lines[progressIndex] = renderProgressBar(100);
          }
          return lines.join('\n').replace('[5/5] Starting VM...', '[5/5] ✓ VM created!');
        });

        setOutput((prev) => prev + '\n\n✅ VM created successfully!\n\n⚠️  Could not open UTM: ' + error.message + '\n\nTo start:\n  1. Open UTM application\n  2. Find "' + name + '" in the list\n  3. Click play to start');
      }

      setTimeout(() => setScreen('create-complete'), 100);

    } catch (error: any) {
      setOutput(`❌ Error creating VM:\n\n${error.message}`);
      setTimeout(() => setScreen('create-complete'), 3000);
    }
  };

  // Wizard Step 1: Select VM Type
  if (screen === 'create-select-type') {
    const vmTypes: MenuItem[] = [
      {
        label: '🍎 test-macos',
        value: 'test-macos',
        description: 'Fully automated test environment (clones base VM)',
        color: 'green',
      },
    ];

    return (
      <Box flexDirection="column" paddingX={2}>
        <Box marginBottom={1}>
          <Text color="cyan">Step {currentStep}/2: </Text>
          <Text bold>Select VM Type</Text>
        </Box>
        <SelectMenu
          title="🖥️  Create Test VM"
          prompt="This will clone your base VM for testing"
          items={vmTypes}
          onSelect={(value) => {
            const defaultName = getDefaultVMName(value);
            setVMConfig({
              type: value,
              name: defaultName,
              memory: '8192',
              cpus: '4',
              diskSize: '80G'
            });
            setCurrentStep(2);
            setScreen('create-confirm');
          }}
          onCancel={() => setScreen('main')}
        />
      </Box>
    );
  }

  // Wizard Step 2: Enter VM Name
  if (screen === 'create-enter-name') {
    const defaultName = getDefaultVMName(vmConfig.type || 'vm');

    return (
      <Box flexDirection="column" paddingX={2}>
        <Box marginBottom={1}>
          <Text color="cyan">Step {currentStep}/4: </Text>
          <Text bold>VM Name</Text>
        </Box>
        <Box marginBottom={1}>
          <Text dimColor>Enter a name for your {vmConfig.type} VM</Text>
        </Box>
        <TextInput
          label="VM Name"
          placeholder={defaultName}
          defaultValue=""
          onSubmit={(value) => {
            setVMConfig({ ...vmConfig, name: value || defaultName });
            setCurrentStep(3);

            // Auto-fill resources with defaults
            const defaults = getSystemResources();
            setVMConfig({
              ...vmConfig,
              name: value || defaultName,
              memory: defaults.memory,
              cpus: defaults.cpus,
              diskSize: defaults.diskSize
            });
            setCurrentStep(4);
            setScreen('create-confirm');
          }}
          onCancel={() => {
            setCurrentStep(1);
            setScreen('create-select-type');
          }}
        />
      </Box>
    );
  }

  // Wizard Step 2: Confirm Configuration
  if (screen === 'create-confirm') {
    return (
      <Box flexDirection="column" paddingX={2}>
        <Box marginBottom={1}>
          <Text color="cyan">Step {currentStep}/2: </Text>
          <Text bold>Confirm Configuration</Text>
        </Box>

        <BorderedBox color="green">
          <Text bold color="green">Test VM Configuration</Text>
          <Box marginTop={1} flexDirection="column">
            <Text>• Type: <Text color="cyan">{vmConfig.type}</Text></Text>
            <Text>• Name: <Text color="cyan">{vmConfig.name}</Text></Text>
            <Text>• Clone of: <Text color="yellow">macOS-base</Text></Text>
          </Box>
          <Box marginTop={1}>
            <Text dimColor>The VM will be cloned, configured, and started automatically.</Text>
          </Box>
        </BorderedBox>

        <Box marginTop={1}>
          <Text bold color="yellow">Create and start this test VM?</Text>
        </Box>
        <Box marginTop={1} flexDirection="column">
          <Text><Text color="green">[y]</Text> Yes, create and start VM</Text>
          <Text><Text color="red">[n]</Text> No, cancel</Text>
        </Box>
      </Box>
    );
  }

  // Executing or Complete
  if (screen === 'create-executing' || screen === 'create-complete') {
    return (
      <Box flexDirection="column" width={80}>
        <Box marginBottom={1}>
          <Text bold color="cyan">
            {screen === 'create-executing' ? '⚙️  Creating VM' : '✓ VM Creation Complete'}
          </Text>
        </Box>

        <BorderedBox color="cyan">
          <Text>{output}</Text>
        </BorderedBox>

        {screen === 'create-complete' && (
          <Box marginTop={1}>
            <Text dimColor>Press any key to return to VM Manager</Text>
          </Box>
        )}
      </Box>
    );
  }

  // List VMs
  if (screen === 'list') {
    return (
      <Box flexDirection="column" width={80}>
        <Box marginBottom={1}>
          <Text bold color="cyan">📋 VM List</Text>
        </Box>

        <BorderedBox color="cyan">
          <Text>{output}</Text>
        </BorderedBox>

        <Box marginTop={1}>
          <Text dimColor>Press any key to return</Text>
        </Box>
      </Box>
    );
  }

  // Main VM Manager Menu
  return (
    <Box flexDirection="column" width={80}>
      <Box marginBottom={1}>
        <Text bold color="green"> 🖥️  TEST VM MANAGER </Text>
        <Text dimColor>  Fully automated test environment</Text>
      </Box>

      <Box marginBottom={1}>
        <BorderedBox color="green">
          <Box flexDirection="column">
            <Text bold color="green">🍎 test-macos VM</Text>
            <Text dimColor>Safe, isolated macOS environment for testing</Text>
            <Box marginTop={1} flexDirection="column">
              <Text>• 100% automated - zero manual steps</Text>
              <Text>• Clones base VM instantly</Text>
              <Text>• Auto-starts ready to test</Text>
              <Text>• Easy cleanup when done</Text>
            </Box>
          </Box>
        </BorderedBox>
      </Box>

      <BorderedBox color="yellow">
        <Box flexDirection="column">
          <Text bold color="yellow">⚡ Quick Actions</Text>

          <Box marginTop={1} flexDirection="column">
            <Box marginBottom={1}>
              <Text bold color="cyan">[1]</Text>
              <Text>  ➕ Create test VM (fully automated)</Text>
            </Box>
            <Box marginBottom={1}>
              <Text bold color="cyan">[2]</Text>
              <Text>  📋 List all VMs</Text>
            </Box>
          </Box>

          <Box marginTop={1} paddingTop={1} borderStyle="single" borderTop>
            <Text bold color="red">[0]</Text>
            <Text>  ← Back to dashboard</Text>
          </Box>
        </Box>
      </BorderedBox>

      <Box marginTop={1}>
        <Text dimColor>Press 1 to create a test VM - it clones, configures, and starts automatically!</Text>
      </Box>
    </Box>
  );
}
