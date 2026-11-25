# services.cadre.buzz: ACP agents as members of a Buzz team chat.
#
# Each agent is a buzz-acp bridge on the relay: it listens for @mentions,
# prompts the configured ACP harness (goose, buzz-agent, pi-acp, or amp-acp),
# and posts replies in the channel while inference stays on local compute.
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
  agentsLib = import ../shared/agents.nix { inherit lib; };

  baseUrl =
    if cfg.backend == "ollama" then "http://127.0.0.1:11434/v1" else "http://127.0.0.1:9337/v1";

  harnessPkgFor =
    h:
    {
      goose = pkgs.goose-cli;
      buzz-agent = pkgs.buzz-agent or null;
      pi-acp = pkgs.pi-acp or null;
      amp-acp = pkgs.amp-acp or null;
    }
    .${h};

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

  piModelsConfig =
    agent:
    (pkgs.formats.json { }).generate "pi-models.json" {
      providers.cadre = {
        inherit baseUrl;
        api = "openai-completions";
        apiKey = "cadre-local";
        models = [
          { id = agent.model; }
        ]
        ++ lib.optional (agent.model != "cadre") {
          id = "cadre";
        };
      };
    };

  piSettingsConfig =
    agent:
    (pkgs.formats.json { }).generate "pi-settings.json" {
      defaultProvider = "cadre";
      defaultModel = agent.model;
      quietStartup = true;
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
          Because the ACP agent runs autonomously inside the service sandbox,
          tools executed by the agent share its user environment and could read the key.
        '';
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.externalPath;
        default = null;
        example = "/run/secrets/buzz-amp.env";
        description = ''
          Optional systemd `EnvironmentFile` supplying harness credentials
          (required with `AMP_API_KEY` when `harness = "amp-acp"`).
        '';
      };

      harness = lib.mkOption {
        type = lib.types.enum agentsLib.harnesses;
        default = "goose";
        description = ''
          ACP agent binary spawned by `buzz-acp`: `goose` (`goose acp`),
          `buzz-agent`, `pi-acp`, or `amp-acp`.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = if cfg.backend == "ollama" then "qwen2.5-coder" else "cadre";
        defaultText = lib.literalExpression ''if config.services.cadre.backend == "ollama" then "qwen2.5-coder" else "cadre"'';
        description = ''
          Model requested for ACP turns: with MeshLLM, "cadre" lets the backend pick;
          with Ollama, must match a model served by Ollama (defaults to "qwen2.5-coder").
        '';
      };

      contextLimit = lib.mkOption {
        type = lib.types.ints.positive;
        default = 32768;
        description = "Context limit in tokens exposed to Goose for compaction planning.";
      };

      systemPrompt = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional persona system prompt injected via `BUZZ_ACP_SYSTEM_PROMPT_FILE`.";
      };

      sessionPolicy = lib.mkOption {
        type = lib.types.enum [
          "channel"
          "thread"
        ];
        default = "channel";
        description = ''
          ACP session scoping in channels (`channel` shares one session per channel;
          `thread` isolates each canonical channel thread).
        '';
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
    let
      harnessPkg = harnessPkgFor agent.harness;
      promptFile = pkgs.writeText "cadre-buzz-${name}-prompt.md" (agent.systemPrompt or "");
    in
    lib.nameValuePair "cadre-buzz-${name}" {
      description = "Cadre agent ${name} (${agent.harness} in Buzz via ${cfg.backend})";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
      ]
      ++ lib.optional (cfg.backend == "mesh") "mesh-llm.service"
      ++ lib.optional (cfg.backend == "ollama") "ollama.service";
      path = lib.optional (harnessPkg != null) harnessPkg ++ [
        pkgs.buzz-cli
        pkgs.git
        pkgs.coreutils
      ];
      environment = {
        HOME = "/var/lib/cadre-buzz-${name}";
        BUZZ_RELAY_URL = agent.relayUrl;
        BUZZ_ACP_AGENT_COMMAND = agent.harness;
        # Non-goose ACP adapters read NDJSON directly on stdio without an `acp` subcommand.
        BUZZ_ACP_AGENT_ARGS = if agent.harness == "goose" then "acp" else "";
        BUZZ_ACP_MODEL = if agent.harness == "pi-acp" then "cadre/${agent.model}" else agent.model;
        BUZZ_ACP_SESSION_POLICY = agent.sessionPolicy;
        BUZZ_ACP_RESPOND_TO = agent.respondTo;
        GOOSE_TELEMETRY_OFF = "1";
      }
      // lib.optionalAttrs (agent.harness == "goose") {
        GOOSE_PROVIDER = "cadre";
        GOOSE_MODEL = agent.model;
        # No human approves tool calls in a chat; the unit is the sandbox.
        GOOSE_MODE = "auto";
      }
      // lib.optionalAttrs (agent.harness == "buzz-agent") {
        BUZZ_AGENT_PROVIDER = "openai";
        OPENAI_COMPAT_BASE_URL = baseUrl;
        OPENAI_COMPAT_API = "chat";
        OPENAI_COMPAT_API_KEY = "cadre-local";
        BUZZ_AGENT_MODEL = agent.model;
      }
      // lib.optionalAttrs (agent.systemPrompt != null) {
        BUZZ_ACP_SYSTEM_PROMPT_FILE = "${promptFile}";
      }
      // lib.optionalAttrs (agent.owner != null) {
        BUZZ_ACP_AGENT_OWNER = agent.owner;
      }
      // lib.optionalAttrs (agent.allowlist != [ ]) {
        BUZZ_ACP_RESPOND_TO_ALLOWLIST = lib.concatStringsSep "," agent.allowlist;
      };
      script = ''
        ${lib.optionalString (agent.harness == "goose") ''
          install -D -m 0644 ${agentProvider agent} "$HOME/.config/goose/custom_providers/cadre.json"
        ''}
        ${lib.optionalString (agent.harness == "pi-acp") ''
          install -D -m 0644 ${piModelsConfig agent} "$HOME/.pi/agent/models.json"
          install -D -m 0644 ${piSettingsConfig agent} "$HOME/.pi/agent/settings.json"
        ''}
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
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        UMask = "0077";
      }
      // lib.optionalAttrs (agent.environmentFile != null) {
        EnvironmentFile = agent.environmentFile;
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
          harness = "goose";
        };
      }
    '';
    description = ''
      ACP agents as members of a Buzz relay, one buzz-acp harness each, all
      backed by this node's local inference (MeshLLM or Ollama).
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.buzz.agents != { }) {
    assertions =
      (lib.mapAttrsToList (name: _: {
        assertion = builtins.match "^[a-zA-Z0-9_-]+$" name != null;
        message = "services.cadre.buzz.agents name '${name}' must match ^[a-zA-Z0-9_-]+$";
      }) cfg.buzz.agents)
      ++ (lib.mapAttrsToList (name: agent: {
        assertion = harnessPkgFor agent.harness != null;
        message = "services.cadre.buzz.agents.${name}: harness package '${agent.harness}' is unavailable (for unfree harnesses such as 'amp-acp', enable allowUnfree).";
      }) cfg.buzz.agents)
      ++ (lib.mapAttrsToList (name: agent: {
        assertion = agent.harness != "amp-acp" || agent.environmentFile != null;
        message = "services.cadre.buzz.agents.${name}: harness = \"amp-acp\" requires environmentFile (with AMP_API_KEY) because amp-acp authenticates against Amp rather than the local inference endpoint.";
      }) cfg.buzz.agents);

    warnings = lib.concatLists (
      lib.mapAttrsToList (
        name: agent:
        lib.optional (agent.respondTo == "owner-only" && agent.owner == null)
          "services.cadre.buzz.agents.${name} has respondTo = \"owner-only\" with owner = null; the agent will ignore all messages."
      ) cfg.buzz.agents
    );

    systemd.services = lib.mapAttrs' agentService cfg.buzz.agents;
  };
}
