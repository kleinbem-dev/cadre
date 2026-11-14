# services.cadre for home-manager: private AI teammates on your own compute.
# User service on any Linux (systemd) or macOS (launchd), NixOS or not.
{ packages }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cadre;
  flakePkgs = packages.${pkgs.stdenv.hostPlatform.system};
  # nixpkgs ships an unrelated Ruby gem at `pkgs.cadre`, so only prefer `pkgs.cadre`
  # when the user applied this flake's overlay (`cadre-ai` is unambiguous).
  isOurCadre = pkg: (pkg.meta.homepage or "") == "https://github.com/kleinbem-dev/cadre";
  stack = lib.mapAttrs (
    name: package:
    if name == "cadre" then
      if pkgs ? cadre && isOurCadre pkgs.cadre then pkgs.cadre else pkgs.cadre-ai or package
    else
      pkgs.${name} or package
  ) flakePkgs;

  cadrePkg = stack.cadre.override {
    mesh-llm = if cfg.backend == "mesh" then cfg.package else null;
  };

  configFile = (pkgs.formats.toml { }).generate "mesh-llm-config.toml" {
    version = 1;
    models = map (model: { inherit model; }) cfg.models;
  };

  baseUrl =
    if cfg.backend == "ollama" then "http://127.0.0.1:11434/v1" else "http://127.0.0.1:9337/v1";

  defaultModel =
    if cfg.models != [ ] then
      builtins.head cfg.models
    else if cfg.backend == "ollama" then
      "qwen2.5-coder"
    else
      "Qwen3-8B-Q4_K_M";

  providerConfig = {
    name = "cadre";
    engine = "openai";
    display_name = "cadre local inference";
    description = "Local inference via ${cfg.backend}";
    api_key_env = "";
    base_url = baseUrl;
    models = [
      {
        name = defaultModel;
        context_limit = 32768;
      }
    ]
    ++ lib.optional (cfg.backend != "ollama" && defaultModel != "cadre") {
      name = "cadre";
      context_limit = 32768;
    };
    timeout_seconds = 600;
    supports_streaming = true;
    requires_auth = false;
  };

  node = pkgs.writeShellScript "cadre-mesh-node" ''
    ${
      if cfg.models != [ ] then
        ''${lib.getExe' pkgs.coreutils "install"} -D -m 0600 ${configFile} "$HOME/.mesh-llm/config.toml"''
      else
        ''${lib.getExe' pkgs.coreutils "rm"} -f "$HOME/.mesh-llm/config.toml"''
    }
    exec ${
      lib.escapeShellArgs (
        [
          (lib.getExe cfg.package)
          "serve"
          "--log-format"
          "json"
          "--bind-port"
          (toString cfg.meshPort)
        ]
        ++ lib.optionals (cfg.joinFile != null) [
          "--join-file"
          cfg.joinFile
        ]
        ++ cfg.extraArgs
      )
    }
  '';
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
        With Ollama, ensure your selected model is pulled before first launch
        (e.g. `ollama pull qwen2.5-coder`).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = stack.mesh-llm;
      defaultText = lib.literalExpression "cadre.packages.\${system}.mesh-llm";
      description = "The MeshLLM package, with the native runtimes your GPU needs (when using mesh backend).";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Qwen3-8B-Q4_K_M" ];
      description = ''
        Models this node serves. For the mesh backend (`backend = "mesh"`),
        names from MeshLLM's catalog or paths to GGUF files. For Ollama
        (`backend = "ollama"`), model names pulled from Ollama (e.g. `[ "qwen2.5-coder" ]`).
      '';
    };

    joinFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/user/1000/secrets/cadre-join";
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

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for `mesh-llm serve` (when using mesh backend).";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the node at login. Off, start it by hand (for mesh: `systemctl --user
        start mesh-llm` or `launchctl start org.nix-community.home.mesh-llm`;
        for ollama: `systemctl --user start ollama` or `launchctl start org.nix-community.home.ollama`):
        a big model holds its memory as long as the node runs.
      '';
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
        with desktop application menu entries.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.goose.enable || (cfg.desktop.enable && pkgs.stdenv.hostPlatform.isLinux)) {
        home.packages = [ cadrePkg ];
      })

      (lib.mkIf cfg.goose.enable {
        home.packages = [ stack.goose-cli ];
        # goose otherwise asks to share usage data, with yes preselected.
        home.sessionVariables = {
          GOOSE_TELEMETRY_OFF = lib.mkDefault "1";
          CADRE_BACKEND = lib.mkDefault cfg.backend;
        };
        xdg.configFile = {
          "goose/custom_providers/cadre.json".text = builtins.toJSON providerConfig;
        };
      })

      (lib.mkIf (cfg.desktop.enable && pkgs.stdenv.hostPlatform.isLinux) {
        home.packages = lib.concatLists [
          (lib.optional (stack ? berd) stack.berd)
          (lib.optional (stack ? buzz-app) stack.buzz-app)
        ];
        xdg.desktopEntries = lib.mkMerge [
          (lib.optionalAttrs (stack ? berd) {
            cadre-berd = {
              name = "Cadre (Berd)";
              comment = "Private AI teammates on desktop (Goose over local inference)";
              exec = "cadre gui";
              icon = "berd";
              categories = [ "Development" ];
              terminal = false;
            };
          })
          (lib.optionalAttrs (stack ? buzz-app) {
            cadre-buzz = {
              name = "Cadre (Buzz)";
              comment = "Buzz team chat with autonomous Cadre AI teammates";
              exec = "cadre chat";
              icon = "buzz";
              categories = [
                "Network"
                "Chat"
              ];
              terminal = false;
            };
          })
        ];
      })

      (lib.mkIf (cfg.backend == "ollama") {
        services.ollama.enable = lib.mkDefault true;
        systemd.user.services.ollama.Install.WantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
        launchd.agents.ollama.config.RunAtLoad = lib.mkIf (!cfg.autoStart) (lib.mkForce false);
        launchd.agents.ollama.config.KeepAlive = lib.mkIf (!cfg.autoStart) (lib.mkForce false);
      })

      (lib.mkIf (cfg.backend == "mesh" && pkgs.stdenv.hostPlatform.isLinux) {
        systemd.user.services.mesh-llm = {
          Unit = {
            Description = "MeshLLM node";
            After = [ "network-online.target" ];
          };
          Service = {
            ExecStart = "${node}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = lib.mkIf cfg.autoStart {
            WantedBy = [ "default.target" ];
          };
        };
      })

      (lib.mkIf (cfg.backend == "mesh" && pkgs.stdenv.hostPlatform.isDarwin) {
        launchd.agents.mesh-llm = {
          enable = true;
          config = {
            ProgramArguments = [ "${node}" ];
            RunAtLoad = cfg.autoStart;
            KeepAlive = {
              Crashed = true;
            };
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mesh-llm.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mesh-llm.log";
          };
        };
      })
    ]
  );
}
