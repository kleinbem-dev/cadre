# services.cadre: private AI teammates on your own compute.
#
# Connects Goose and ACP agents to your choice of local inference backend:
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
  agentsLib = import ../shared/agents.nix { inherit lib; };

  cadrePkg = pkgs.cadre.override {
    mesh-llm = if cfg.backend == "mesh" then cfg.package else null;
  };

  agentsJson = (pkgs.formats.json { }).generate "cadre-agents.json" (
    agentsLib.serializeAgents {
      inherit (cfg) agents;
      defaultBackend = cfg.backend;
    }
  );

  harnessPkgFor =
    h:
    {
      goose = pkgs.goose-cli;
      buzz-agent = pkgs.buzz-agent or null;
      pi-acp = pkgs.pi-acp or null;
      amp-acp = pkgs.amp-acp or null;
    }
    .${h};

  agentHarnessPkgs = lib.unique (
    lib.filter (p: p != null) (map (a: harnessPkgFor a.harness) (lib.attrValues cfg.agents))
  );
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

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the backend at boot. Off, it starts only by hand
        (e.g. `systemctl start mesh-llm` or `systemctl start ollama`):
        on a workstation, a big model's memory otherwise sits in swap all day.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments for `mesh-llm serve` (when using mesh backend).";
    };

    web = {
      enable = lib.mkEnableOption "the Cadre web dashboard service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8384;
        description = "Port to serve the Cadre web dashboard on.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        example = "127.0.0.1";
        description = "Listen IP address for the web dashboard.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to open the web dashboard port in the firewall.";
      };

      enableChatProxy = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable the `/api/chat` completion proxy when `listenAddress`
          is non-loopback (for example `0.0.0.0` behind an authenticated proxy).
          Loopback listeners (`127.0.0.1`, `::1`, `localhost`) always allow `/api/chat`.
        '';
      };

      package = lib.mkPackageOption pkgs "cadre-web" {
        default = [ "cadre-web" ];
        extraDescription = "The built Cadre web dashboard static package.";
      };
    };

    goose.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install goose and cadre CLI, set up for the local node.";
    };

    tools.enable = lib.mkEnableOption "Block builder toolkit (review, ai-rules, braindump, buzz-cli)";

    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install Cadre desktop surfaces (Berd GUI and Buzz team chat)
        alongside the CLI.
      '';
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule agentsLib.agentSubmodule);
      default = { };
      example = lib.literalExpression ''
        {
          reviewer = {
            name = "Cadre Reviewer";
            role = "Code Reviewer & Security Auditor";
            harness = "goose";
            tools = [ "git" "review" ];
          };
        }
      '';
      description = ''
        Declarative AI teammates exposed to `cadre session --agent <id>`,
        `cadre agents`, and the Cadre web dashboard.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      (lib.mapAttrsToList (name: _: {
        assertion = builtins.match "^[a-zA-Z0-9_-]+$" name != null;
        message = "services.cadre.agents name '${name}' must match ^[a-zA-Z0-9_-]+$";
      }) cfg.agents)
      ++ (lib.mapAttrsToList (name: agent: {
        assertion = harnessPkgFor agent.harness != null;
        message = "services.cadre.agents.${name}: harness package '${agent.harness}' is unavailable (for unfree harnesses such as 'amp-acp', enable allowUnfree).";
      }) cfg.agents);

    services = {
      ollama = lib.mkIf (cfg.backend == "ollama") {
        enable = lib.mkDefault true;
        loadModels = lib.mkIf (cfg.models != [ ]) cfg.models;
      };

      mesh-llm = lib.mkIf (cfg.backend == "mesh") {
        enable = true;
        inherit (cfg) package meshPort openFirewall;
        settings = lib.mkIf (cfg.models != [ ]) {
          version = 1;
          models = map (model: { inherit model; }) cfg.models;
        };
        # The service's user can't read a file only root can, so systemd reads
        # it as a credential.
        extraArgs =
          lib.optionals (cfg.joinFile != null) [
            "--join-file"
            "%d/join"
          ]
          ++ cfg.extraArgs;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.web.enable && cfg.web.openFirewall) [
      cfg.web.port
    ];

    systemd.services = {
      ollama.wantedBy = lib.mkIf (cfg.backend == "ollama" && !cfg.autoStart) (lib.mkForce [ ]);
      ollama-model-loader.wantedBy = lib.mkIf (cfg.backend == "ollama" && !cfg.autoStart) (
        lib.mkForce [ ]
      );

      mesh-llm = lib.mkIf (cfg.backend == "mesh") {
        wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
        serviceConfig.LoadCredential = lib.mkIf (cfg.joinFile != null) [
          "join:${cfg.joinFile}"
        ];
      };

      cadre-web = lib.mkIf cfg.web.enable {
        description = "Cadre web dashboard";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs (
            [
              (lib.getExe pkgs.python3)
              "${cadrePkg}/libexec/cadre/server.py"
              "--host"
              cfg.web.listenAddress
              "--port"
              (toString cfg.web.port)
              "--static-dir"
              "${cfg.web.package}"
              "--backend"
              cfg.backend
            ]
            ++ lib.optional (cfg.models != [ ]) "--default-model=${builtins.head cfg.models}"
            ++ lib.optional (cfg.agents != { }) "--agents-file=${agentsJson}"
            ++ lib.optional cfg.web.enableChatProxy "--enable-chat-proxy"
          );
          Restart = "on-failure";
          RestartSec = 5;
          DynamicUser = true;
          UMask = "0077";
          CapabilityBoundingSet = "";
          LockPersonality = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
        };
      };
    };

    environment = lib.mkMerge [
      (lib.mkIf (cfg.agents != { }) {
        etc."cadre/agents.json".source = agentsJson;
        systemPackages = agentHarnessPkgs;
      })
      (lib.mkIf (cfg.goose.enable || cfg.tools.enable || cfg.desktop.enable) {
        systemPackages = [ cadrePkg ];
      })
      (lib.mkIf cfg.goose.enable {
        systemPackages = [ pkgs.goose-cli ];
        # goose otherwise asks to share usage data, with yes preselected.
        sessionVariables = {
          GOOSE_TELEMETRY_OFF = lib.mkDefault "1";
          CADRE_BACKEND = lib.mkDefault cfg.backend;
        };
      })
      (lib.mkIf cfg.tools.enable {
        systemPackages = lib.concatLists [
          (lib.optional (pkgs ? block-review) pkgs.block-review)
          (lib.optional (pkgs ? ai-rules) pkgs.ai-rules)
          (lib.optional (pkgs ? braindump) pkgs.braindump)
          (lib.optional (pkgs ? buzz-cli) pkgs.buzz-cli)
        ];
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
