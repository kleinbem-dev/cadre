# services.cadre.buzz: goose agents as members of a Buzz team chat.
#
# Each agent is a buzz-acp harness on the relay: it listens for @mentions,
# prompts goose over ACP, and goose answers in the channel. goose runs on
# the local inference node (services.cadre: MeshLLM or Ollama), so the whole
# conversation stays on your machines.
#
# An agent needs its own Nostr key, registered as a member of the relay:
#   buzz-admin generate-key   → the secret key into `privateKeyFile`
#   buzz-admin add-member --pubkey <public key>
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cadre;

  # goose's provider for the local inference backend (MeshLLM or Ollama).
  baseUrl =
    if cfg.backend == "ollama" then "http://127.0.0.1:11434/v1" else "http://127.0.0.1:9337/v1";

  agentProvider =
    agent:
    (pkgs.formats.json { }).generate "cadre.json" {
      name = "cadre";
      display_name = "cadre local inference";
      description = "Local inference via ${cfg.backend}";
      engine = "openai";
      base_url = baseUrl;
      api_key_env = "";
      requires_auth = false;
      supports_streaming = true;
      timeout_seconds = 600;
      models = [
        {
          name = agent.model;
          context_limit = agent.contextLimit;
        }
      ]
      ++ lib.optional (agent.model != "cadre") {
        name = "cadre";
        context_limit = agent.contextLimit;
      };
    };

  agentModule = {
    options = {
      relayUrl = lib.mkOption {
        type = lib.types.str;
        example = "wss://buzz.example.com";
        description = "WebSocket URL of the Buzz relay.";
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.externalPath;
        example = "/run/secrets/buzz-agent-key";
        description = ''
          File with the agent's Nostr secret key (`nsec1…` or hex). This MUST be a
          dedicated, throwaway identity for this bot, never your personal Nostr key.
          Because Goose runs with `GOOSE_MODE = "auto"` inside the service sandbox,
          tools executed by the agent share its user environment and could read the key.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = if cfg.backend == "ollama" then "qwen2.5-coder" else "cadre";
        defaultText = lib.literalExpression ''if config.services.cadre.backend == "ollama" then "qwen2.5-coder" else "cadre"'';
        description = ''
          Model for goose: with MeshLLM, "cadre" lets the backend pick;
          with Ollama, must match a model served by Ollama (defaults to "qwen2.5-coder").
        '';
      };

      contextLimit = lib.mkOption {
        type = lib.types.ints.positive;
        default = if cfg.backend == "ollama" then 4096 else 32768;
        defaultText = lib.literalExpression ''if config.services.cadre.backend == "ollama" then 4096 else 32768'';
        description = "Context limit in tokens exposed to Goose for compaction planning.";
      };

      owner = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        description = ''
          Your hex public key. The agent answers its owner, and only its owner
          by default: without one it answers nobody.
        '';
      };

      respondTo = lib.mkOption {
        type = lib.types.enum [
          "owner-only"
          "allowlist"
          "anyone"
          "nobody"
        ];
        default = "owner-only";
        description = ''
          Whose messages the agent answers (buzz-acp's author gate).
          Defaults to `owner-only`. Warning: with `anyone` or `allowlist`, accepted
          chat members can prompt the agent into executing tools without human approval,
          and the service has network access and holds the agent's Nostr key.
        '';
      };

      allowlist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Hex public keys the agent answers besides its owner, with `respondTo = \"allowlist\"`.";
      };
    };
  };

  agentService =
    name: agent:
    lib.nameValuePair "cadre-buzz-${name}" {
      description = "Cadre agent ${name} (goose in Buzz via ${cfg.backend})";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
      ]
      ++ lib.optional (cfg.backend == "mesh") "mesh-llm.service";
      path = [
        pkgs.goose-cli
        pkgs.buzz-cli
        pkgs.git
        pkgs.coreutils
      ];
      environment = {
        HOME = "/var/lib/cadre-buzz-${name}";
        BUZZ_RELAY_URL = agent.relayUrl;
        BUZZ_ACP_RESPOND_TO = agent.respondTo;
        GOOSE_PROVIDER = "cadre";
        GOOSE_MODEL = agent.model;
        # No human approves tool calls in a chat; the unit is the sandbox.
        GOOSE_MODE = "auto";
        GOOSE_TELEMETRY_OFF = "1";
      }
      // lib.optionalAttrs (agent.owner != null) {
        BUZZ_ACP_AGENT_OWNER = agent.owner;
      }
      // lib.optionalAttrs (agent.allowlist != [ ]) {
        BUZZ_ACP_RESPOND_TO_ALLOWLIST = lib.concatStringsSep "," agent.allowlist;
      };
      script = ''
        install -D -m 0644 ${agentProvider agent} "$HOME/.config/goose/custom_providers/cadre.json"
        BUZZ_PRIVATE_KEY=$(< "$CREDENTIALS_DIRECTORY/key")
        export BUZZ_PRIVATE_KEY
        unset CREDENTIALS_DIRECTORY
        exec ${lib.getExe' pkgs.buzz-acp "buzz-acp"}
      '';
      serviceConfig = {
        LoadCredential = [ "key:${agent.privateKeyFile}" ];
        DynamicUser = true;
        StateDirectory = "cadre-buzz-${name}";
        WorkingDirectory = "/var/lib/cadre-buzz-${name}";
        Restart = "on-failure";
        RestartSec = 10;

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
      };
    };
in
{
  options.services.cadre.buzz.agents = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule agentModule);
    default = { };
    example = lib.literalExpression ''
      {
        helper = {
          relayUrl = "wss://buzz.example.com";
          privateKeyFile = "/run/secrets/buzz-helper-key";
        };
      }
    '';
    description = ''
      goose agents as members of a Buzz relay, one buzz-acp harness each, all
      backed by this node's local inference (MeshLLM or Ollama).
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.buzz.agents != { }) {
    systemd.services = lib.mapAttrs' agentService cfg.buzz.agents;
  };
}
