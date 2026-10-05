# Local DeepSeek inference through DS4 and the Pi coding agent.
{ pkgs, username, ... }:

let
  userHome = "/Users/${username}";
  ds4RuntimeDir = "${userHome}/src/ai/ds4";
  piDs4Dir = "${userHome}/src/ai/pi-ds4";

  localAiSetup = pkgs.writeShellApplication {
    name = "local-ai-setup";
    runtimeInputs = with pkgs; [
      coreutils
      gnumake
    ];
    text = builtins.readFile ../../../tools/local-ai/setup.sh;
  };

  localAiDoctor = pkgs.writeShellApplication {
    name = "local-ai-doctor";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = builtins.readFile ../../../tools/local-ai/doctor.sh;
  };
in
{
  projects.sets = [
    (import ../../projects/local-ai.nix)
  ];

  apps = {
    useBaseLists = true;
    brewsToAdd = [
      "pi-coding-agent"
    ];
  };

  environment = {
    systemPackages = [
      localAiSetup
      localAiDoctor
    ];
    variables = {
      DS4_RUNTIME_DIR = ds4RuntimeDir;
      PI_DS4_DIR = piDs4Dir;
    };
  };

  home-manager.users.${username}.home.file.".pi/ds4/settings.json".text = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/mitsuhiko/pi-ds4/main/settings.schema.json";
    protocol = "openai-responses";
    runtimeDir = ds4RuntimeDir;
    autoUpdate = false;
    contextTokens = 32768;
    power = 70;
    readyTimeoutMs = 900000;
  };
}
