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

interface ImportNode {
  file: string;
  fullPath: string;
  imports: ImportNode[];
  depth: number;
  packages?: {
    brew: string[];
    cask: string[];
    nix: string[];
  };
}

interface ConfigInspectorProps {
  onBack: () => void;
}

type ViewMode = 'menu' | 'packages' | 'files' | 'dependencies' | 'host-flow';

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
  const [hostname, setHostname] = useState<string>('');
  const [hostConfigPath, setHostConfigPath] = useState<string>('');
  const [importTree, setImportTree] = useState<ImportNode | null>(null);

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
      } else if (input === '4') {
        setViewMode('host-flow');
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

  useEffect(() => {
    // When host config is detected, build the import tree
    if (hostConfigPath) {
      buildHostImportTree();
    }
  }, [hostConfigPath]);

  // Helper function to find the project root (directory containing flake.nix)
  const findProjectRoot = (): string => {
    let currentDir = process.cwd();

    // Check current directory
    if (fs.existsSync(path.join(currentDir, 'flake.nix'))) {
      return currentDir;
    }

    // Check parent directory
    const parentDir = path.dirname(currentDir);
    if (fs.existsSync(path.join(parentDir, 'flake.nix'))) {
      return parentDir;
    }

    // If still not found, return current directory as fallback
    console.warn('Could not find flake.nix in current or parent directory');
    return currentDir;
  };

  const detectHostConfig = async () => {
    try {
      // Get hostname
      const { stdout: hostnameOutput } = await execAsync('hostname -s');
      const detectedHostname = hostnameOutput.trim();
      setHostname(detectedHostname);

      // Look for host config file
      const projectRoot = findProjectRoot();
      const hostsDir = path.join(projectRoot, 'hosts');

      if (!fs.existsSync(hostsDir)) {
        console.log('No hosts directory found');
        return;
      }

      // Try to read flake.nix to determine machine type
      let machineType: string | null = null;
      try {
        const flakePath = path.join(projectRoot, 'flake.nix');
        const flakeContent = fs.readFileSync(flakePath, 'utf-8');

        // Look for this hostname's configuration in flake.nix
        const hostConfigPattern = new RegExp(`"${detectedHostname}"\\s*=\\s*mkDarwinSystem\\s*\\{[\\s\\S]*?machineType\\s*=\\s*"([^"]+)"`, 'm');
        const match = flakeContent.match(hostConfigPattern);

        if (match) {
          machineType = match[1];
          console.log(`Detected machine type: ${machineType}`);
        }
      } catch (error) {
        console.error('Failed to parse flake.nix for machine type:', error);
      }

      // Build module load order based on flake.nix mkDarwinSystem structure:
      // 1. hosts/shared/default.nix
      // 2. hosts/${machineType}/default.nix (if specified)
      // 3. hosts/${hostname}/default.nix (if exists)
      // 4. modules/home-manager/default.nix (via home-manager.users.${username})

      console.log(`Building module chain for: ${detectedHostname}${machineType ? ` (${machineType})` : ''}`);

      // Strategy 1: Use shared as base (always loaded first in flake)
      const sharedHostNix = path.join(hostsDir, 'shared', 'default.nix');
      if (fs.existsSync(sharedHostNix)) {
        const relativePath = path.relative(projectRoot, sharedHostNix);
        setHostConfigPath(relativePath);
        console.log(`Using base config: ${relativePath}`);
        return;
      }

      // Strategy 2: If no shared, try machine type
      if (machineType) {
        const machineTypePath = path.join(hostsDir, machineType, 'default.nix');
        if (fs.existsSync(machineTypePath)) {
          const relativePath = path.relative(projectRoot, machineTypePath);
          setHostConfigPath(relativePath);
          console.log(`Using machine type config: ${relativePath}`);
          return;
        }
      }

      // Strategy 3: Try exact hostname match
      const exactHostDir = path.join(hostsDir, detectedHostname);
      const exactHostNix = path.join(exactHostDir, 'default.nix');

      if (fs.existsSync(exactHostNix)) {
        const relativePath = path.relative(projectRoot, exactHostNix);
        setHostConfigPath(relativePath);
        console.log(`Found exact host config: ${relativePath}`);
        return;
      }

      // Strategy 4: Find any host config as last resort
      const hostEntries = fs.readdirSync(hostsDir, { withFileTypes: true });
      for (const entry of hostEntries) {
        if (entry.isDirectory() && entry.name !== 'profiles') {
          const hostDir = path.join(hostsDir, entry.name);
          const defaultNix = path.join(hostDir, 'default.nix');

          if (fs.existsSync(defaultNix)) {
            const relativePath = path.relative(projectRoot, defaultNix);
            setHostConfigPath(relativePath);
            console.log(`Found fallback host config: ${relativePath}`);
            return;
          }
        }
      }
    } catch (error) {
      console.error('Failed to detect host config:', error);
    }
  };

  const loadConfigStructure = async () => {
    setLoading(true);
    try {
      const projectRoot = findProjectRoot();

      // Detect host configuration
      await detectHostConfig();

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

      // Remove heredoc blocks first (string templates that contain code examples)
      // Pattern: << 'EOL' ... EOL or << EOL ... EOL
      let cleanedContent = content.replace(/<<\s*'?(\w+)'?[\s\S]*?\n\1/g, '');

      // Also remove multi-line strings between '' or ""
      cleanedContent = cleanedContent.replace(/''[\s\S]*?''/g, '');
      cleanedContent = cleanedContent.replace(/"(?:[^"\\]|\\.)*"/g, '');

      // Match imports = [ ... ] - can span multiple lines
      const importMatch = cleanedContent.match(/imports\s*=\s*\[([\s\S]*?)\];/);
      if (importMatch) {
        const importBlock = importMatch[1];

        // Split by lines and filter out commented lines
        const lines = importBlock.split('\n');
        const activeLines = lines
          .filter(line => {
            const trimmed = line.trim();
            // Skip empty lines and comments
            return trimmed.length > 0 && !trimmed.startsWith('#');
          })
          .join('\n');

        // Extract paths from non-commented lines only
        const importPaths = activeLines.match(/[\(]?\s*(\.\.?\/[^\s\)\]"';]+)/g) || [];
        imports.push(...importPaths.map(p => {
          // Clean up the path - remove parentheses, quotes, etc.
          let cleaned = p.trim()
            .replace(/^\(?\s*/, '')  // Remove leading paren and spaces
            .replace(/["'\s\)]/g, ''); // Remove quotes, spaces, closing paren
          return cleaned;
        }));
      }

      // Match direct import statements: import ./path or import ../path (non-commented)
      const lines = cleanedContent.split('\n');
      const activeContent = lines
        .filter(line => !line.trim().startsWith('#'))
        .join('\n');

      const directImports = activeContent.match(/import\s+(\.\.?\/[^\s;]+)/g) || [];
      imports.push(...directImports.map(i => {
        return i.replace('import ', '').trim().replace(/["';]/g, '');
      }));

      // Also match <./path> or <../path> style imports (non-commented)
      const angleImports = activeContent.match(/<(\.\.?\/[^>]+)>/g) || [];
      imports.push(...angleImports.map(i => i.replace(/[<>]/g, '')));

      // Remove duplicates and filter empty strings
      return [...new Set(imports)].filter(imp => imp.length > 0);
    } catch (error) {
      console.error(`Error extracting imports from ${filePath}:`, error);
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
          if (entry.name === 'node_modules') continue; // Skip node_modules

          const fullPath = path.join(dir, entry.name);
          const relativePath = basePath ? path.join(basePath, entry.name) : entry.name;

          if (entry.isDirectory()) {
            files.push(...findNixFiles(fullPath, relativePath));
          } else if (entry.name.endsWith('.nix')) {
            files.push(relativePath);
          }
        }
      } catch (error) {
        console.error(`Error reading directory ${dir}:`, error);
      }
      return files;
    };

    const nixFiles = findNixFiles(rootPath);
    console.log(`Found ${nixFiles.length} .nix files`);

    for (const file of nixFiles) {
      const fullPath = path.join(rootPath, file);
      const imports = await extractImports(fullPath);
      // Include all files, even those with no imports, so we can see everything
      deps.push({ file, imports });
    }

    // Sort by number of imports (most complex first)
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

  const extractPackagesFromFile = async (filePath: string): Promise<{brew: string[], cask: string[], nix: string[]}> => {
    const pkgs = { brew: [] as string[], cask: [] as string[], nix: [] as string[] };

    try {
      const content = fs.readFileSync(filePath, 'utf-8');

      // Extract homebrew formulas - multiple patterns
      // Pattern 1: brews = [ ... ];
      const brewMatch1 = content.match(/brews\s*=\s*\[([\s\S]*?)\];/);
      if (brewMatch1) {
        const brewList = brewMatch1[1].match(/"([^"]+)"/g) || [];
        pkgs.brew.push(...brewList.map(b => b.replace(/"/g, '')));
      }

      // Pattern 2: homebrew.brews = ...
      const brewMatch2 = content.match(/homebrew\.brews\s*=\s*(?:lib\.mkDefault\s*)?\(?\s*(?:if[\s\S]*?then\s*)?\(?(?:lib\.subtractLists[\s\S]*?\))?\s*\+\+\s*[\s\S]*?\)?\s*;/);
      // This pattern is complex, let's try a simpler approach - just look for the baseLists definition

      // Extract homebrew casks - multiple patterns
      // Pattern 1: casks = [ ... ];
      const caskMatch1 = content.match(/casks\s*=\s*\[([\s\S]*?)\];/);
      if (caskMatch1) {
        const caskList = caskMatch1[1].match(/"([^"]+)"/g) || [];
        pkgs.cask.push(...caskList.map(c => c.replace(/"/g, '')));
      }

      // Extract nix packages - multiple patterns
      // Pattern 1: environment.systemPackages with pkgs
      const nixMatch1 = content.match(/environment\.systemPackages\s*=[\s\S]*?with\s+pkgs;?\s*\[([\s\S]*?)\];/);
      if (nixMatch1) {
        const nixList = nixMatch1[1].match(/[\w.-]+/g) || [];
        pkgs.nix.push(...nixList.filter(p => p !== 'with' && p !== 'pkgs'));
      }

      // Pattern 2: systemPackages = [ ... ]; in let blocks
      const nixMatch2 = content.match(/systemPackages\s*=\s*\[([\s\S]*?)\];/);
      if (nixMatch2) {
        const nixList = nixMatch2[1].match(/"([^"]+)"/g) || [];
        pkgs.nix.push(...nixList.map(n => n.replace(/"/g, '')));
      }

      // Pattern 3: home.packages
      const homeMatch = content.match(/home\.packages\s*=[\s\S]*?with\s+pkgs;?\s*\[([\s\S]*?)\];/);
      if (homeMatch) {
        const homeList = homeMatch[1].match(/[\w.-]+/g) || [];
        pkgs.nix.push(...homeList.filter(p => p !== 'with' && p !== 'pkgs'));
      }

      // Remove duplicates
      pkgs.brew = [...new Set(pkgs.brew)];
      pkgs.cask = [...new Set(pkgs.cask)];
      pkgs.nix = [...new Set(pkgs.nix)];
    } catch (error) {
      console.error(`Error extracting packages from ${filePath}:`, error);
    }

    return pkgs;
  };

  const getActualModuleOrder = async (): Promise<string[]> => {
    try {
      const projectRoot = findProjectRoot();
      const detectedHostname = hostname || 'nabucodonosor'; // Use detected hostname

      // Build the expected module order based on flake.nix structure
      const moduleOrder: string[] = [];

      // Read flake.nix to understand the structure
      const flakePath = path.join(projectRoot, 'flake.nix');
      const flakeContent = fs.readFileSync(flakePath, 'utf-8');

      // Extract machine type from flake
      const hostConfigPattern = new RegExp(`"${detectedHostname}"\\s*=\\s*mkDarwinSystem\\s*\\{[\\s\\S]*?machineType\\s*=\\s*"([^"]+)"`, 'm');
      const match = flakeContent.match(hostConfigPattern);
      const machineType = match ? match[1] : null;

      console.log(`Getting actual module order for ${detectedHostname}${machineType ? ` (${machineType})` : ''}`);

      // The mkDarwinSystem function loads modules in this order:
      // 1. hosts/shared
      const sharedPath = path.join(projectRoot, 'hosts', 'shared', 'default.nix');
      if (fs.existsSync(sharedPath)) {
        moduleOrder.push(path.relative(projectRoot, sharedPath));
      }

      // 2. hosts/${machineType} (if specified)
      if (machineType) {
        const machineTypePath = path.join(projectRoot, 'hosts', machineType, 'default.nix');
        if (fs.existsSync(machineTypePath)) {
          moduleOrder.push(path.relative(projectRoot, machineTypePath));
        }
      }

      // 3. hosts/${hostname} (if exists and different from machineType)
      if (detectedHostname !== machineType) {
        const hostPath = path.join(projectRoot, 'hosts', detectedHostname, 'default.nix');
        if (fs.existsSync(hostPath)) {
          moduleOrder.push(path.relative(projectRoot, hostPath));
        }
      }

      // 4. modules/home-manager (loaded via home-manager.users.${username})
      const homeManagerPath = path.join(projectRoot, 'modules', 'home-manager', 'default.nix');
      if (fs.existsSync(homeManagerPath)) {
        moduleOrder.push(path.relative(projectRoot, homeManagerPath));
      }

      console.log('Actual module load order:', moduleOrder);
      return moduleOrder;
    } catch (error) {
      console.error('Failed to determine actual module order:', error);
      return [];
    }
  };

  const buildImportTreeFromModuleOrder = async (): Promise<ImportNode | null> => {
    const projectRoot = findProjectRoot();
    const moduleOrder = await getActualModuleOrder();

    if (moduleOrder.length === 0) {
      console.error('No modules found in load order');
      return null;
    }

    // Build tree starting with the first module (hosts/shared)
    const rootPath = path.join(projectRoot, moduleOrder[0]);
    const rootNode = await buildImportTree(rootPath, 0, new Set());

    if (!rootNode) {
      return null;
    }

    // Now we need to inject the other top-level modules into the tree
    // They should appear as siblings to the modules/darwin import
    const visited = new Set<string>();
    visited.add(path.join(projectRoot, moduleOrder[0]));

    for (let i = 1; i < moduleOrder.length; i++) {
      const modulePath = path.join(projectRoot, moduleOrder[i]);

      if (visited.has(modulePath)) {
        continue;
      }
      visited.add(modulePath);

      const moduleNode = await buildImportTree(modulePath, 1, visited);
      if (moduleNode && rootNode.imports) {
        // Insert at the appropriate position
        rootNode.imports.push(moduleNode);
      }
    }

    return rootNode;
  };

  const buildImportTree = async (filePath: string, depth: number = 0, visited: Set<string> = new Set()): Promise<ImportNode | null> => {
    try {
      const projectRoot = findProjectRoot();
      const absolutePath = path.isAbsolute(filePath) ? filePath : path.join(projectRoot, filePath);

      // Avoid circular dependencies
      if (visited.has(absolutePath)) {
        return null;
      }
      visited.add(absolutePath);

      // Check if file exists
      if (!fs.existsSync(absolutePath)) {
        console.error(`File not found: ${absolutePath}`);
        return null;
      }

      // Extract imports from this file
      const imports = await extractImports(absolutePath);

      // Extract packages from this file
      const filePkgs = await extractPackagesFromFile(absolutePath);

      // Build the import nodes recursively
      const importNodes: ImportNode[] = [];
      for (const imp of imports) {
        // Resolve relative import to absolute path
        const importDir = path.dirname(absolutePath);
        const resolvedPath = path.resolve(importDir, imp);

        // If it's a directory, look for default.nix
        let targetPath = resolvedPath;
        if (fs.existsSync(resolvedPath) && fs.statSync(resolvedPath).isDirectory()) {
          targetPath = path.join(resolvedPath, 'default.nix');
        }

        // Recursively build the tree for this import
        const childNode = await buildImportTree(targetPath, depth + 1, new Set(visited));
        if (childNode) {
          importNodes.push(childNode);
        }
      }

      // Create the node with packages
      const node: ImportNode = {
        file: path.relative(projectRoot, absolutePath),
        fullPath: absolutePath,
        imports: importNodes,
        depth: depth,
        packages: (filePkgs.brew.length > 0 || filePkgs.cask.length > 0 || filePkgs.nix.length > 0)
          ? filePkgs
          : undefined
      };

      return node;
    } catch (error) {
      console.error(`Error building import tree for ${filePath}:`, error);
      return null;
    }
  };

  const buildHostImportTree = async () => {
    console.log(`Building complete import tree with actual module load order`);

    // Use the new function that respects flake.nix module order
    const tree = await buildImportTreeFromModuleOrder();
    setImportTree(tree);
    console.log('Import tree built:', tree);
  };

  const renderImportTree = (node: ImportNode, isLast: boolean = true, prefix: string = ''): React.ReactNode[] => {
    const elements: React.ReactNode[] = [];
    const connector = isLast ? '└─ ' : '├─ ';
    const fileName = path.basename(node.file);
    const dirName = path.dirname(node.file);

    // Color based on file type/location
    let color = 'magenta';
    if (node.file.includes('hosts/')) color = 'cyan';
    else if (node.file.includes('modules/')) color = 'yellow';
    else if (node.file.includes('home-configurations/')) color = 'green';

    // Calculate total packages
    const totalPkgs = node.packages
      ? (node.packages.brew.length + node.packages.cask.length + node.packages.nix.length)
      : 0;

    elements.push(
      <Box key={node.file}>
        <Text dimColor>{prefix}{node.depth > 0 ? connector : ''}</Text>
        <Text color={color}>📄 {fileName}</Text>
        <Text dimColor> ({dirName})</Text>
        {totalPkgs > 0 && (
          <Text bold color="green"> [{totalPkgs} pkg{totalPkgs > 1 ? 's' : ''}]</Text>
        )}
      </Box>
    );

    // Show package details if this file has packages
    if (node.packages && totalPkgs > 0) {
      const pkgPrefix = prefix + (node.depth > 0 ? (isLast ? '   ' : '│  ') : '');

      if (node.packages.brew.length > 0) {
        elements.push(
          <Box key={`${node.file}-brew`} marginLeft={4}>
            <Text dimColor>{pkgPrefix}  🍺 brew: </Text>
            <Text color="magenta">{node.packages.brew.join(', ')}</Text>
          </Box>
        );
      }

      if (node.packages.cask.length > 0) {
        elements.push(
          <Box key={`${node.file}-cask`} marginLeft={4}>
            <Text dimColor>{pkgPrefix}  📱 cask: </Text>
            <Text color="cyan">{node.packages.cask.join(', ')}</Text>
          </Box>
        );
      }

      if (node.packages.nix.length > 0) {
        elements.push(
          <Box key={`${node.file}-nix`} marginLeft={4}>
            <Text dimColor>{pkgPrefix}  ❄️  nix:  </Text>
            <Text color="blue">{node.packages.nix.join(', ')}</Text>
          </Box>
        );
      }
    }

    if (node.imports && node.imports.length > 0) {
      const newPrefix = prefix + (node.depth > 0 ? (isLast ? '   ' : '│  ') : '');
      node.imports.forEach((child, index) => {
        const childIsLast = index === node.imports.length - 1;
        elements.push(...renderImportTree(child, childIsLast, newPrefix));
      });
    }

    return elements;
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

                <Box marginTop={1} marginBottom={1}>
                  <Text bold color="blue">[4]</Text>
                  <Text>  📊 This Host's Configuration Flow</Text>
                </Box>
                <Box marginLeft={4}>
                  <Text dimColor>See how THIS machine's config is built & what packages it installs</Text>
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
    if (dependencies.length === 0) {
      return (
        <Box flexDirection="column" width={100}>
          <Box marginBottom={1}>
            <Text bold color="magenta"> 🔗 FILE DEPENDENCIES </Text>
            <Text dimColor>  Analyzing file relationships...</Text>
          </Box>

          <BorderedBox color="magenta">
            <Box flexDirection="column">
              <Text color="yellow">⚠️  No dependencies found yet</Text>
              <Box marginTop={1}>
                <Text dimColor>This might mean:</Text>
              </Box>
              <Box marginTop={1} flexDirection="column">
                <Text>• The analysis is still loading</Text>
                <Text>• No .nix files have imports statements</Text>
                <Text>• There may be an issue parsing the files</Text>
              </Box>
              <Box marginTop={1}>
                <Text dimColor>Project root: {findProjectRoot()}</Text>
              </Box>
            </Box>
          </BorderedBox>

          <Box marginTop={1}>
            <Text bold color="red">[0]</Text>
            <Text>  ← Back to inspector menu</Text>
          </Box>
        </Box>
      );
    }

    const visibleStart = Math.max(0, selectedIndex - 10);
    const visibleEnd = Math.min(dependencies.length, selectedIndex + 10);
    const visibleDeps = dependencies.slice(visibleStart, visibleEnd);

    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="magenta"> 🔗 FILE DEPENDENCIES </Text>
          <Text dimColor>  Which files import which ({dependencies.length} total files)</Text>
        </Box>

        <BorderedBox color="magenta">
          <Box flexDirection="column">
            <Text bold color="cyan">Import Relationships (sorted by most imports)</Text>
            <Text dimColor>Navigate with ↑↓ arrows, selected file shows what it imports</Text>
            <Box marginTop={1} flexDirection="column">
              {visibleDeps.length === 0 ? (
                <Text color="yellow">No files visible in this range</Text>
              ) : (
                visibleDeps.map((dep, index) => {
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
                      {isSelected && dep.imports.length > 0 && dep.imports.map((imp, i) => (
                        <Box key={i} marginLeft={4}>
                          <Text dimColor>  ├─ </Text>
                          <Text color="magenta">{imp}</Text>
                        </Box>
                      ))}
                      {isSelected && dep.imports.length === 0 && (
                        <Box marginLeft={4}>
                          <Text dimColor>  (no imports)</Text>
                        </Box>
                      )}
                    </Box>
                  );
                })
              )}
            </Box>
            <Box marginTop={1}>
              <Text dimColor>Showing {visibleStart + 1}-{Math.min(visibleEnd, dependencies.length)} of {dependencies.length}</Text>
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

  // Host Configuration Flow View
  if (viewMode === 'host-flow') {
    return (
      <Box flexDirection="column" width={100}>
        <Box marginBottom={1}>
          <Text bold color="blue"> 📊 HOST CONFIGURATION FLOW </Text>
          <Text dimColor>  How THIS machine's config is built</Text>
        </Box>

        <BorderedBox color="blue">
          <Box flexDirection="column">
            <Text bold color="cyan">🖥️  Machine Information</Text>
            <Box marginTop={1} flexDirection="column">
              <Box>
                <Text dimColor>Hostname: </Text>
                <Text bold color="green">{hostname || 'detecting...'}</Text>
              </Box>
              <Box>
                <Text dimColor>Host Config: </Text>
                <Text bold color="yellow">{hostConfigPath || 'searching...'}</Text>
              </Box>
            </Box>

            {!hostConfigPath && (
              <Box marginTop={1} flexDirection="column">
                <Text color="yellow">⚠️  No host configuration found</Text>
                <Box marginTop={1}>
                  <Text dimColor>Looking in: hosts/*/default.nix</Text>
                </Box>
              </Box>
            )}
          </Box>
        </BorderedBox>

        {importTree && (
          <Box marginTop={1}>
            <BorderedBox color="cyan">
              <Box flexDirection="column">
                <Text bold color="cyan">🔗 Configuration Import Chain</Text>
                <Text dimColor>Files are loaded in this order (tree shows inheritance)</Text>
                <Box marginTop={1} flexDirection="column">
                  {renderImportTree(importTree)}
                </Box>
                <Box marginTop={1}>
                  <Text dimColor>Color legend: </Text>
                  <Text color="cyan">hosts</Text>
                  <Text dimColor> | </Text>
                  <Text color="yellow">modules</Text>
                  <Text dimColor> | </Text>
                  <Text color="green">home-configurations</Text>
                </Box>
              </Box>
            </BorderedBox>
          </Box>
        )}

        {hostConfigPath && !importTree && (
          <Box marginTop={1}>
            <BorderedBox color="yellow">
              <Box flexDirection="column">
                <Text color="yellow">⏳ Building import tree...</Text>
                <Text dimColor>Tracing all configuration dependencies...</Text>
              </Box>
            </BorderedBox>
          </Box>
        )}

        <Box marginTop={1}>
          <Text bold color="red">[0]</Text>
          <Text>  ← Back to inspector menu</Text>
        </Box>
      </Box>
    );
  }

  return null;
}
