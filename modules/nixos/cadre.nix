# services.cadre: private AI teammates on your own compute.
#
# Connects Goose agents to your choice of local inference backend:
#   - MeshLLM (services.mesh-llm): distributed inference across your machines
#   - Ollama: local runner on this device
#
# Talk to the local API (http://127.0.0.1:9337/v1 or :11434/v1).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cadre;
in
{
  options.services.cadre = {
    enable = lib.mkEnableOption "cadre: private AI teammates on your own compute";

    backend = lib.mkOption {
      type = lib.types.enum [
        "mesh"
        "ollama"
      ];
      default = "mesh";
      description = ''
        The local inference backend: mesh (MeshLLM) or ollama.
        With Ollama, models configured in `services.cadre.models` are loaded
        automatically via `services.ollama.loadModels`.
      '';
    };

    package = lib.mkPackageOption pkgs "mesh-llm" {
      example = "mesh-llm-cuda";
      extraDescription = "Pick the variant with the native runtimes your GPU needs (when using mesh backend).";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Qwen3-8B-Q4_K_M" ];
      description = ''
        Models this node serves. For the mesh backend (`backend = "mesh"`),
        names from MeshLLM's catalog (`mesh-llm models recommended`, downloaded at
        the first start) or paths to GGUF files. For Ollama (`backend = "ollama"`),
        model names pulled from the Ollama library (e.g. `[ "qwen2.5-coder" ]`).
        Empty serves none: in mesh mode, the node only routes to the others.
      '';
    };

    joinFile = lib.mkOption {
      type = lib.types.nullOr lib.types.externalPath;
      default = null;
      example = "/run/secrets/cadre-join";
      description = ''
        File with the mesh's invite token. `null` creates a mesh of its own:
        the first node.
      '';
    };

    meshPort = lib.mkOption {
      type = lib.types.port;
      default = 7842;
      description = "UDP port for the mesh's traffic between nodes.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the mesh port for the other nodes.";
    };

    goose.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install goose and cadre CLI, set up for the local node.";
    };

    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install Cadre desktop surfaces (Berd GUI and Buzz team chat)
        alongside the CLI.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = lib.mkIf (cfg.backend == "ollama") {
      enable = lib.mkDefault true;
      loadModels = lib.mkIf (cfg.models != [ ]) cfg.models;
    };

    services.mesh-llm = lib.mkIf (cfg.backend == "mesh") {
      enable = true;
      inherit (cfg) package meshPort openFirewall;
      settings = lib.mkIf (cfg.models != [ ]) {
        version = 1;
        models = map (model: { inherit model; }) cfg.models;
      };
      # The service's user can't read a file only root can, so systemd reads
      # it as a credential.
      extraArgs = lib.optionals (cfg.joinFile != null) [
        "--join-file"
        "%d/join"
      ];
    };

    systemd.services.mesh-llm = lib.mkIf (cfg.backend == "mesh" && cfg.joinFile != null) {
      serviceConfig.LoadCredential = [
        "join:${cfg.joinFile}"
      ];
    };

    environment = lib.mkMerge [
      (lib.mkIf cfg.goose.enable {
        systemPackages = [
          pkgs.goose-cli
          pkgs.cadre
        ];
        # goose otherwise asks to share usage data, with yes preselected.
        sessionVariables = {
          GOOSE_TELEMETRY_OFF = lib.mkDefault "1";
          CADRE_BACKEND = lib.mkDefault cfg.backend;
        };
      })
      (lib.mkIf cfg.desktop.enable {
        systemPackages = lib.concatLists [
          (lib.optional (pkgs ? berd) pkgs.berd)
          (lib.optional (pkgs ? buzz-app) pkgs.buzz-app)
        ];
      })
    ];
  };
}
