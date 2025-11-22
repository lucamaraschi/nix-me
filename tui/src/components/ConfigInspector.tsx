import React, { useState, useEffect } from 'react';
import { Box, Text, useInput } from 'ink';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';

const execAsync = promisify(exec);

interface TreeNode {
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: TreeNode[];
  imports?: string[];
  size?: number;
}

interface Dependency {
  file: string;
  imports: string[];
}

interface ConfigInspectorProps {
  onBack: () => void;
}

type ViewMode = 'menu' | 'packages' | 'files' | 'dependencies';

function BorderedBox({ children, color = 'white', title }: { children: React.ReactNode; color?: string; title?: string }) {
  return (
    <Box flexDirection="column" borderStyle="round" borderColor={color} padding={1}>
      {title && <Text bold color={color}>{title}</Text>}
      {children}
    </Box>
  );
}

export function ConfigInspector({ onBack }: ConfigInspectorProps) {
  const [viewMode, setViewMode] = useState<ViewMode>('menu');
  const [fileTree, setFileTree] = useState<TreeNode | null>(null);
  const [dependencies, setDependencies] = useState<Dependency[]>([]);
  const [packages, setPackages] = useState<{brew: string[], cask: string[], nix: string[]}>({
    brew: [],
    cask: [],
    nix: []
  });
  const [loading, setLoading] = useState(true);
  const [selectedIndex, setSelectedIndex] = useState(0);

  useInput((input, key) => {
    if (input === '0' || key.escape) {
      if (viewMode === 'menu') {
        onBack();
      } else {
        setViewMode('menu');
        setSelectedIndex(0);
      }
    } else if (input === 'q') {
      onBack();
    } else if (viewMode === 'menu') {
      if (input === '1') {
        setViewMode('packages');
      } else if (input === '2') {
        setViewMode('files');
      } else if (input === '3') {
        setViewMode('dependencies');
      }
    } else if (key.upArrow || input === 'k') {
      if (viewMode === 'dependencies') {
        setSelectedIndex(prev => Math.max(0, prev - 1));
      }
    } else if (key.downArrow || input === 'j') {
      if (viewMode === 'dependencies') {
        setSelectedIndex(prev => Math.min(dependencies.length - 1, prev + 1));
      }
    }
  });

  useEffect(() => {
    loadConfigStructure();
  }, []);

  const loadConfigStructure = async () => {
    setLoading(true);
    try {
      const projectRoot = process.cwd();

      // Build file tree
      const tree = await buildFileTree(projectRoot);
      setFileTree(tree);

      // Analyze dependencies
      const deps = await analyzeDependencies(projectRoot);
      setDependencies(deps);

      // Extract packages
      const pkgs = await extractPackages(projectRoot);
      setPackages(pkgs);
    } catch (error) {
      console.error('Failed to load config structure:', error);
    }
    setLoading(false);
  };

  const buildFileTree = async (rootPath: string): Promise<TreeNode> => {
    const importantDirs = ['hosts', 'modules', 'home-configurations'];
    const importantFiles = ['flake.nix'];

    const tree: TreeNode = {
      name: 'nix-me',
      path: rootPath,
      type: 'directory',
      children: []
    };

    // Add important files first
    for (const file of importantFiles) {
      const filePath = path.join(rootPath, file);
      if (fs.existsSync(filePath)) {
        const imports = await extractImports(filePath);
        const stats = fs.statSync(filePath);
        tree.children!.push({
          name: file,
          path: filePath,
          type: 'file',
          imports,
          size: stats.size
        });
      }
    }

    // Add important directories
    for (const dir of importantDirs) {
      const dirPath = path.join(rootPath, dir);
      if (fs.existsSync(dirPath)) {
        tree.children!.push(await buildDirTree(dirPath, dir));
      }
    }

    return tree;
  };

  const buildDirTree = async (dirPath: string, name: string): Promise<TreeNode> => {
    const node: TreeNode = {
      name,
      path: dirPath,
      type: 'directory',
      children: []
    };

    try {
      const entries = fs.readdirSync(dirPath, { withFileTypes: true });

      for (const entry of entries) {
        if (entry.name.startsWith('.')) continue;

        const fullPath = path.join(dirPath, entry.name);

        if (entry.isDirectory()) {
          node.children!.push(await buildDirTree(fullPath, entry.name));
        } else if (entry.name.endsWith('.nix')) {
          const imports = await extractImports(fullPath);
          const stats = fs.statSync(fullPath);
          node.children!.push({
            name: entry.name,
            path: fullPath,
            type: 'file',
            imports,
            size: stats.size
          });
        }
      }
    } catch (error) {
      // Ignore permission errors
    }

    return node;
  };

  const extractImports = async (filePath: string): Promise<string[]> => {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const imports: string[] = [];

      // Match imports = [ ... ]
      const importMatch = content.match(/imports\s*=\s*\[([\s\S]*?)\];/);
      if (importMatch) {
        const importBlock = importMatch[1];
        // Extract paths like ./path or ../path
        const importPaths = importBlock.match(/\.\.?\/[^\s\]]+/g) || [];
        imports.push(...importPaths.map(p => p.replace(/["'\s]/g, '')));
      }

      // Match direct imports
      const directImports = content.match(/import\s+(\.\.?\/[^\s;]+)/g) || [];
      imports.push(...directImports.map(i => i.replace('import ', '').trim().replace(/["';]/g, '')));

      return [...new Set(imports)];
    } catch (error) {
      return [];
    }
  };

  const analyzeDependencies = async (rootPath: string): Promise<Dependency[]> => {
    const deps: Dependency[] = [];

    const findNixFiles = (dir: string, basePath: string = ''): string[] => {
      const files: string[] = [];
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
          if (entry.name.startsWith('.')) continue;
          const fullPath = path.join(dir, entry.name);
          const relativePath = path.join(basePath, entry.name);

          if (entry.isDirectory()) {
            files.push(...findNixFiles(fullPath, relativePath));
          } else if (entry.name.endsWith('.nix')) {
            files.push(relativePath);
          }
        }
      } catch (error) {
        // Ignore errors
      }
      return files;
    };

    const nixFiles = findNixFiles(rootPath);

    for (const file of nixFiles) {
      const fullPath = path.join(rootPath, file);
      const imports = await extractImports(fullPath);
      if (imports.length > 0) {
        deps.push({ file, imports });
      }
    }

    return deps.sort((a, b) => b.imports.length - a.imports.length);
  };

  const extractPackages = async (rootPath: string): Promise<{brew: string[], cask: string[], nix: string[]}> => {
    const pkgs = { brew: [] as string[], cask: [] as string[], nix: [] as string[] };

    try {
      // Find all .nix files
      const findNixFiles = (dir: string): string[] => {
        const files: string[] = [];
        try {
          const entries = fs.readdirSync(dir, { withFileTypes: true });
          for (const entry of entries) {
            if (entry.name.startsWith('.')) continue;
            const fullPath = path.join(dir, entry.name);
            if (entry.isDirectory()) {
              files.push(...findNixFiles(fullPath));
            } else if (entry.name.endsWith('.nix')) {
              files.push(fullPath);
            }
          }
        } catch (error) {}
        return files;
      };

      const nixFiles = findNixFiles(rootPath);

      for (const file of nixFiles) {
        const content = fs.readFileSync(file, 'utf-8');

        // Extract homebrew formulas
        const brewMatch = content.match(/brews\s*=\s*\[([\s\S]*?)\];/);
        if (brewMatch) {
          const brewList = brewMatch[1].match(/"([^"]+)"/g) || [];
          pkgs.brew.push(...brewList.map(b => b.replace(/"/g, '')));
        }

        // Extract homebrew casks
        const caskMatch = content.match(/casks\s*=\s*\[([\s\S]*?)\];/);
        if (caskMatch) {
          const caskList = caskMatch[1].match(/"([^"]+)"/g) || [];
          pkgs.cask.push(...caskList.map(c => c.replace(/"/g, '')));
        }

        // Extract nix packages
        const nixMatch = content.match(/environment\.systemPackages\s*=\s*with\s+pkgs;\s*\[([\s\S]*?)\];/);
        if (nixMatch) {
          const nixList = nixMatch[1].match(/[\w-]+/g) || [];
          pkgs.nix.push(...nixList);
        }
      }

      pkgs.brew = [...new Set(pkgs.brew)].sort();
      pkgs.cask = [...new Set(pkgs.cask)].sort();
      pkgs.nix = [...new Set(pkgs.nix)].sort();
    } catch (error) {}

    return pkgs;
  };

  const renderTree = (node: TreeNode, depth: number = 0, isLast: boolean = true, prefix: string = ''): React.ReactNode[] => {
    const elements: React.ReactNode[] = [];
    const connector = isLast ? '└─ ' : '├─ ';
    const icon = node.type === 'directory' ? '📁' : '📄';
    const color = node.type === 'directory' ? 'cyan' : node.name.endsWith('.nix') ? 'magenta' : 'white';

    elements.push(
      <Box key={node.path}>
        <Text dimColor>{prefix}{depth > 0 ? connector : ''}</Text>
        <Text color={color}>{icon} {node.name}</Text>
        {node.imports && node.imports.length > 0 && (
          <Text dimColor> ({node.imports.length})</Text>
        )}
      </Box>
    );

    if (node.children && node.children.length > 0) {
      const newPrefix = prefix + (depth > 0 ? (isLast ? '   ' : '│  ') : '');
      node.children.forEach((child, index) => {
        const childIsLast = index === node.children!.length - 1;
        elements.push(...renderTree(child, depth + 1, childIsLast, newPrefix));
      });
    }

    return elements;
  };

  if (loading) {
    return (
      <Box flexDirection="column" padding={2}>
        <Text color="cyan">📊 Analyzing configuration structure...</Text>
        <Box marginTop={1}>
          <Text dimColor>• Scanning files...</Text>
        </Box>
        <Box>
          <Text dimColor>• Analyzing dependencies...</Text>
        </Box>
        <Box>
          <Text dimColor>• Extracting packages...</Text>
        </Box>
      </Box>
    );
  }

  // Main menu - let user choose what to inspect
  if (viewMode === 'menu') {
    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="magenta"> 🔍 CONFIGURATION INSPECTOR </Text>
          <Text dimColor>  Understand your nix-me setup</Text>
        </Box>

        <Box flexDirection="column" marginBottom={1}>
          <BorderedBox color="cyan">
            <Box flexDirection="column">
              <Text bold color="cyan">What would you like to inspect?</Text>

              <Box marginTop={1} flexDirection="column">
                <Box marginBottom={1}>
                  <Text bold color="green">[1]</Text>
                  <Text>  📦 View All Installed Packages</Text>
                </Box>
                <Box marginLeft={4}>
                  <Text dimColor>See everything installed via Homebrew (CLI & GUI apps) and Nix</Text>
                </Box>

                <Box marginTop={1} marginBottom={1}>
                  <Text bold color="yellow">[2]</Text>
                  <Text>  🗂️  Browse Configuration Files</Text>
                </Box>
                <Box marginLeft={4}>
                  <Text dimColor>Navigate the file tree to see hosts, modules, and configs</Text>
                </Box>

                <Box marginTop={1} marginBottom={1}>
                  <Text bold color="magenta">[3]</Text>
                  <Text>  🔗 View File Dependencies</Text>
                </Box>
                <Box marginLeft={4}>
                  <Text dimColor>Understand which files import which (dependency graph)</Text>
                </Box>
              </Box>
            </Box>
          </BorderedBox>
        </Box>

        <Box marginTop={1}>
          <Text bold color="red">[0]</Text>
          <Text>  ← Back to dashboard</Text>
        </Box>
      </Box>
    );
  }

  // Files View - Browse Configuration Tree
  if (viewMode === 'files' && fileTree) {
    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="yellow"> 🗂️  CONFIGURATION FILES </Text>
          <Text dimColor>  Browse your nix-me structure</Text>
        </Box>

        <BorderedBox color="yellow">
          <Box flexDirection="column">
            <Text bold color="yellow">📁 nix-me Project Structure</Text>
            <Box marginTop={1} flexDirection="column">
              {renderTree(fileTree)}
            </Box>
          </Box>
        </BorderedBox>

        <Box marginTop={1}>
          <Text dimColor>Numbers (n) show how many files each file imports</Text>
        </Box>

        <Box marginTop={1}>
          <Text bold color="red">[0]</Text>
          <Text>  ← Back to inspector menu</Text>
        </Box>
      </Box>
    );
  }

  // Dependencies View
  if (viewMode === 'dependencies') {
    const visibleStart = Math.max(0, selectedIndex - 10);
    const visibleEnd = Math.min(dependencies.length, selectedIndex + 10);
    const visibleDeps = dependencies.slice(visibleStart, visibleEnd);

    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="magenta"> 🔗 FILE DEPENDENCIES </Text>
          <Text dimColor>  Which files import which ({dependencies.length} total)</Text>
        </Box>

        <BorderedBox color="magenta">
          <Box flexDirection="column">
            <Text bold color="cyan">File Import Relationships</Text>
            <Text dimColor>Use ↑↓ arrows to navigate, selected file shows its imports</Text>
            <Box marginTop={1} flexDirection="column">
              {visibleDeps.map((dep, index) => {
                const actualIndex = visibleStart + index;
                const isSelected = actualIndex === selectedIndex;

                return (
                  <Box key={dep.file} flexDirection="column" marginBottom={1}>
                    <Box>
                      {isSelected ? <Text color="cyan">▶ </Text> : <Text>  </Text>}
                      <Text bold={isSelected} color={isSelected ? 'cyan' : 'white'}>
                        {dep.file}
                      </Text>
                      <Text dimColor> ({dep.imports.length} imports)</Text>
                    </Box>
                    {isSelected && dep.imports.map((imp, i) => (
                      <Box key={i} marginLeft={4}>
                        <Text dimColor>  ├─ </Text>
                        <Text color="magenta">{imp}</Text>
                      </Box>
                    ))}
                  </Box>
                );
              })}
            </Box>
          </Box>
        </BorderedBox>

        <Box marginTop={1}>
          <Text dimColor>↑↓ Navigate | </Text>
          <Text bold color="red">[0]</Text>
          <Text dimColor> Back to menu</Text>
        </Box>
      </Box>
    );
  }

  // Packages View
  if (viewMode === 'packages') {
    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="green"> 📦 PACKAGE SOURCES </Text>
          <Text dimColor>  All packages by installation source</Text>
        </Box>

        <Box flexDirection="column">
          <Box marginBottom={1} width="100%">
            <BorderedBox color="cyan" title="🍺 Homebrew Formulas (CLI Tools)">
              <Text dimColor>Total: {packages.brew.length}</Text>
              <Box marginTop={1} flexDirection="column">
                {packages.brew.slice(0, 10).map(pkg => (
                  <Text key={pkg}>• {pkg}</Text>
                ))}
                {packages.brew.length > 10 && (
                  <Text dimColor>... and {packages.brew.length - 10} more</Text>
                )}
              </Box>
            </BorderedBox>
          </Box>

          <Box marginBottom={1} width="100%">
            <BorderedBox color="magenta" title="📱 Homebrew Casks (GUI Apps)">
              <Text dimColor>Total: {packages.cask.length}</Text>
              <Box marginTop={1} flexDirection="column">
                {packages.cask.slice(0, 10).map(pkg => (
                  <Text key={pkg}>• {pkg}</Text>
                ))}
                {packages.cask.length > 10 && (
                  <Text dimColor>... and {packages.cask.length - 10} more</Text>
                )}
              </Box>
            </BorderedBox>
          </Box>

          <Box width="100%">
            <BorderedBox color="green" title="❄️  Nix Packages">
              <Text dimColor>Total: {packages.nix.length}</Text>
              <Box marginTop={1} flexDirection="column">
                {packages.nix.slice(0, 10).map(pkg => (
                  <Text key={pkg}>• {pkg}</Text>
                ))}
                {packages.nix.length > 10 && (
                  <Text dimColor>... and {packages.nix.length - 10} more</Text>
                )}
              </Box>
            </BorderedBox>
          </Box>
        </Box>

        <Box marginTop={1}>
          <Text bold color="red">[0]</Text>
          <Text>  ← Back to inspector menu</Text>
        </Box>
      </Box>
    );
  }

  return null;
}
