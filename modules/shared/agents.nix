# Shared declarative teammate schema for NixOS and Home Manager modules.
{ lib }:

let
  harnesses = [
    "goose"
    "buzz-agent"
    "pi-acp"
    "amp-acp"
  ];

  agentSubmodule =
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          example = "Cadre Reviewer";
          description = "Display name of the AI teammate.";
        };

        handle = lib.mkOption {
          type = lib.types.str;
          default = "@${name}";
          defaultText = lib.literalExpression ''"@''${name}"'';
          example = "@reviewer";
          description = "Chat handle used in sessions and team channels.";
        };

        role = lib.mkOption {
          type = lib.types.str;
          default = "Autonomous AI Teammate";
          example = "Code Reviewer & Security Auditor";
          description = "Short role title shown in the CLI and web console.";
        };

        description = lib.mkOption {
          type = lib.types.str;
          default = "Private AI teammate running on local compute.";
          description = "Concise persona summary and specialization.";
        };

        avatar = lib.mkOption {
          type = lib.types.str;
          default = "◈";
          example = "🛡️";
          description = "Glyph or emoji icon displayed in the web console.";
        };

        harness = lib.mkOption {
          type = lib.types.enum harnesses;
          default = "goose";
          description = "ACP agent runtime backing this teammate.";
        };

        backend = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "mesh"
              "ollama"
            ]
          );
          default = null;
          description = "Inference backend override (`null` inherits `services.cadre.backend`).";
        };

        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "Qwen3-8B-Q4_K_M";
          description = "Model override (`null` uses the active backend's default model).";
        };

        systemPrompt = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom system instructions applied to interactive and web sessions.";
        };

        tools = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "git"
            "nix"
            "review"
          ];
          description = "Capability tags surfaced in the teammate directory.";
        };
      };
    };

  serializeAgents =
    {
      agents,
      defaultBackend,
      defaultModel,
    }:
    lib.mapAttrsToList (
      id: agent:
      {
        inherit id;
        inherit (agent)
          handle
          name
          role
          description
          avatar
          harness
          tools
          ;
        backend = if agent.backend != null then agent.backend else defaultBackend;
        model = if agent.model != null then agent.model else defaultModel;
      }
      // lib.optionalAttrs (agent.systemPrompt != null) {
        inherit (agent) systemPrompt;
      }
    ) agents;
in
{
  inherit harnesses agentSubmodule serializeAgents;
}
