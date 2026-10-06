# Local DeepSeek inference through DS4 and the Pi coding agent.
{ config, lib, options, pkgs, username, ... }:

let
  models = {
    "dsv4-flash-q2" = {
      displayName = "DeepSeek V4 Flash Q2";
      downloadTarget = "ds4f-q2";
      piModel = "ds4/dsv4-flash-q2";
      modelMarker = "ds4flash.gguf";
      downloadSizeGiB = 81;
      recommendedMemoryGiB = 96;
      requiredFreeDiskGiB = 100;
    };
  };

  cfg = config.localAi;
  selectedModel = models.${cfg.model};
  userHome = "/Users/${username}";
  ds4RuntimeDir = "${userHome}/src/ai/ds4";
  piDs4Dir = "${userHome}/src/ai/pi-ds4";
  modelPath = "${ds4RuntimeDir}/${selectedModel.modelMarker}";
  piModelParts = lib.splitString "/" selectedModel.piModel;
  piProvider = builtins.head piModelParts;
  piModelName = lib.concatStringsSep "/" (builtins.tail piModelParts);

  localAiStateValues = pkgs.writeText "nix-me-local-ai-values.json" (builtins.toJSON {
    "local-ai" = {
      pi_settings = {
        defaultProvider = piProvider;
        defaultModel = piModelName;
      };
      ds4_settings = {
        "$schema" = "https://raw.githubusercontent.com/mitsuhiko/pi-ds4/main/settings.schema.json";
        protocol = "openai-responses";
        runtimeDir = ds4RuntimeDir;
        autoUpdate = false;
        contextTokens = 32768;
        power = 70;
        readyTimeoutMs = 900000;
      };
    };
  });

  localAiPreflight = pkgs.writeShellApplication {
    name = "local-ai-preflight";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = builtins.readFile ../../../tools/local-ai/preflight.sh;
  };

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

  modelEnvironment = {
    LOCAL_AI_MODEL = cfg.model;
    LOCAL_AI_MODEL_NAME = selectedModel.displayName;
    LOCAL_AI_DOWNLOAD_TARGET = selectedModel.downloadTarget;
    LOCAL_AI_PI_MODEL = selectedModel.piModel;
    LOCAL_AI_MODEL_PATH = modelPath;
    LOCAL_AI_DOWNLOAD_SIZE_GIB = toString selectedModel.downloadSizeGiB;
    LOCAL_AI_RECOMMENDED_MEMORY_GIB = toString selectedModel.recommendedMemoryGiB;
    LOCAL_AI_REQUIRED_FREE_DISK_GIB = toString selectedModel.requiredFreeDiskGiB;
    LOCAL_AI_REQUIREMENTS_ENFORCEMENT = cfg.requirements.enforcement;
  };
in
{
  options.localAi = {
    model = lib.mkOption {
      type = lib.types.enum (builtins.attrNames models);
      default = "dsv4-flash-q2";
      description = "Local model configured for DS4 and Pi.";
    };

    requirements = {
      checkOnActivation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to check local model requirements before system activation.";
      };

      enforcement = lib.mkOption {
        type = lib.types.enum [
          "warn"
          "fail"
        ];
        default = "warn";
        description = "Whether capacity shortfalls warn or stop activation.";
      };
    };
  };

  config = {
    projects.sets = [
      (import ../../projects/local-ai.nix)
    ];

    apps = {
      useBaseLists = true;
      brewsToAdd = [
        "pi-coding-agent"
      ];
      state = {
        enable = lib.mkDefault true;
        values = lib.mkAfter (options.apps.state.values.default ++ [ localAiStateValues ]);
      };
    };

    environment = {
      systemPackages = [
        localAiPreflight
        localAiSetup
        localAiDoctor
      ];
      variables = modelEnvironment // {
        DS4_RUNTIME_DIR = ds4RuntimeDir;
        PI_DS4_DIR = piDs4Dir;
      };
    };

    system.activationScripts.preActivation.text =
      lib.mkIf cfg.requirements.checkOnActivation
        (lib.mkAfter ''
          echo "Checking local AI model requirements..." >&2
          LOCAL_AI_HOME=${lib.escapeShellArg userHome} \
          LOCAL_AI_MODEL_NAME=${lib.escapeShellArg selectedModel.displayName} \
          LOCAL_AI_MODEL_PATH=${lib.escapeShellArg modelPath} \
          LOCAL_AI_RECOMMENDED_MEMORY_GIB=${toString selectedModel.recommendedMemoryGiB} \
          LOCAL_AI_REQUIRED_FREE_DISK_GIB=${toString selectedModel.requiredFreeDiskGiB} \
          LOCAL_AI_REQUIREMENTS_ENFORCEMENT=${lib.escapeShellArg cfg.requirements.enforcement} \
            ${localAiPreflight}/bin/local-ai-preflight
        '');

  };
}
