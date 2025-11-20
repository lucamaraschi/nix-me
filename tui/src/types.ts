export interface SystemInfo {
  hostname: string;
  generation: string;
  branch: string;
  uncommitted: number;
  packages: {
    guiApps: number;
    brewCLI: number;
    nixCLI: number;
  };
  updates: number;
}
