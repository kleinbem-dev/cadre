<p align="center">
  <img src="assets/logo.svg" alt="cadre banner" width="680" />
</p>

<p align="center">
  <a href="https://github.com/kleinbem-dev/cadre/actions/workflows/check.yaml"><img src="https://github.com/kleinbem-dev/cadre/actions/workflows/check.yaml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License: MIT"></a>
  <a href="BRANDING.md"><img src="https://img.shields.io/badge/Identity-Cadre%20%E2%97%88-f59e0b?style=flat-square" alt="Branding"></a>
</p>

---

**`cadre`** brings private, autonomous AI teammates directly onto your machines and into your team channels.
Powered by [Goose](https://github.com/aaif-goose/goose) and Agent Client Protocol (ACP) adapters (`goose`, `buzz-agent`, `pi-acp`, `amp-acp`), and backed by your choice of local compute—whether a single [Ollama](https://ollama.ai) instance on your laptop or a distributed [MeshLLM](https://github.com/Mesh-LLM/mesh-llm) cluster split across your GPU boxes.

No cloud API keys required. No telemetry. Inference runs entirely on your hardware (Buzz agents talk only to your configured relays and whatever network resources their tools access).

```bash
nix run github:kleinbem-dev/cadre
```

---

## What It Does

1. **In Team Chat:** Autonomous members of your [Buzz](https://github.com/block/buzz) relays via `buzz-acp`. Team members `@mention` agents in channels or threads to debug code, audit diffs, or run commands (defaults to owner-only authorization; configure `respondTo` for team allowlists or open channels).
2. **In Your Terminal & Editor:** Interactive pairing sessions (`cadre`, `cadre --agent @reviewer`), local multi-pass LLM code review (`cadre review`), cross-agent instruction sync (`cadre rules`), and readiness diagnostics (`cadre doctor`).
3. **Flexible Compute:** Switch between **Ollama** or **MeshLLM** with a single flag. If you have multiple devices, MeshLLM splits models too large for one machine across your fleet.

---

## Architecture & Compute Backends

```text
               ┌────────────────────────────────────────────────────────────────────────────────────────┐
               │                                        SURFACES                                        │
               │  Terminal (cadre)  │  Web Dashboard (cadre web)  │  Desktop (cadre gui)  │  Chat (buzz) │
               └───────────────────────────────────────────┬────────────────────────────────────────────┘
                                   │  ACP (goose · buzz-agent · pi-acp · amp-acp)
                                   ▼
               ┌────────────────────────────────────────────────────────┐
               │                        CADRE                           │
               │     Declarative Teammates, Builder Toolkit & MCP       │
               └───────────────────┬────────────────────────────────────┘
                                   │  OpenAI-Compatible Local API
                                   ▼
        ┌──────────────────────────────────────────────────────────────────────┐
        │                        LOCAL COMPUTE LAYER                           │
        │                                                                      │
        │  [Backend: Ollama]                [Backend: MeshLLM]                 │
        │  Single-node, instant setup       Distributed across fleet           │
        │  localhost:11434                  localhost:9337                     │
        │                                   ┌────────────┐     ┌────────────┐  │
        │                                   │ Laptop (8B)├─────┤ GPU (32B)  │  │
        └───────────────────────────────────┴────────────┴─────┴────────────┴──┘
```

---

## Quickstart

### 1. Run Directly with Nix

The `gui`, `chat`, `review`, and `rules` commands dispatch to `berd`, `buzz-app` (or `buzz`), `block-review` (`review`), and `ai-rules` on `PATH`. Enable `services.cadre.desktop.enable` and `services.cadre.tools.enable` to install them declaratively.

```bash
# Terminal pairing assistant (Goose in CLI):
nix run github:kleinbem-dev/cadre

# Check local inference, ACP harnesses, toolkit, and MCP extension readiness:
nix run github:kleinbem-dev/cadre -- doctor

# Pair with a specific declarative teammate:
cadre --agent @reviewer

# Run local LLM code review over git changes (via block/review):
cadre review -- -base main

# Web Dashboard (SvelteKit + local inference telemetry, MCP readiness & chat):
nix run github:kleinbem-dev/cadre -- web

# Desktop GUI (Berd window on your local backend):
nix run github:kleinbem-dev/cadre -- gui

# Team Chat (Buzz client):
nix run github:kleinbem-dev/cadre -- chat
```

---

## Fleet Setup (NixOS)

Run `cadre` as a system service on your machines (and optionally self-host a Buzz relay via `cadre.nixosModules.buzz-relay`):

```nix
{
  inputs.cadre.url = "github:kleinbem-dev/cadre";

  outputs = { nixpkgs, cadre, ... }: {
    nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
      modules = [
        cadre.nixosModules.default
        {
          services.cadre = {
            enable = true;
            autoStart = true; # or false on workstations so idle memory doesn't starve builds
            tools.enable = true; # installs block-review, ai-rules, braindump, buzz-cli
            desktop.enable = true; # installs Berd GUI and Buzz chat alongside CLI
            backend = "mesh"; # or "ollama"
            models = [ "Qwen3-14B-Q4_K_M" ];
            # package = pkgs.mesh-llm-cuda;  # NVIDIA acceleration

            # Define reusable AI teammates for CLI (`cadre --agent @reviewer`) and Web:
            agents.reviewer = {
              name = "Cadre Reviewer";
              role = "Code Reviewer & Security Auditor";
              harness = "pi-acp"; # goose | buzz-agent | pi-acp | amp-acp
              systemPrompt = "Audit diffs for correctness, security invariants, and simplicity.";
              tools = [ "git" "review" ];
            };

            # Host the Cadre web dashboard daemon:
            web = {
              enable = true;
              port = 8384;
              # enableChatProxy = true; # opt-in /api/chat on non-loopback listeners behind auth
            };

            # Deploy autonomous teammates into your Buzz team chat:
            buzz.agents.dev = {
              relayUrl = "wss://buzz.example.com";
              privateKeyFile = "/run/secrets/buzz-cadre-key";
              harness = "goose"; # goose | buzz-agent | pi-acp | amp-acp
              # environmentFile = "/run/secrets/buzz-amp.env"; # required (AMP_API_KEY) when harness = "amp-acp"
              sessionPolicy = "thread"; # channel | thread
              respondTo = "owner-only"; # or "allowlist", "anyone"
              owner = "hex-pubkey-here";
            };
          };
        }
      ];
    };
  };
}
```

The first machine creates the mesh and prints an invite token at its first start (`journalctl -u mesh-llm`). Other machines join by providing the token in `services.cadre.joinFile`.

---

## Any Linux or macOS (Home Manager)

Run `cadre` as a user service without needing NixOS:

```nix
{
  imports = [ cadre.homeManagerModules.default ];

  services.cadre = {
    enable = true;
    tools.enable = true;
    desktop.enable = true; # adds Cadre (Berd) and Cadre (Buzz) menu entries on Linux
    backend = "mesh";
    models = [ "Qwen3-8B-Q4_K_M" ];
    agents.reviewer = {
      name = "Cadre Reviewer";
      role = "Code Reviewer";
      tools = [ "git" "review" ];
    };
  };
}
```

---

## Ecosystem Packages

`cadre` packages and dogfoods the self-hosted AI agent stack for Nix:

| Package | Purpose |
| :--- | :--- |
| **`cadre`** / **`cadre-ai`** | Unified launcher, readiness doctor, and local telemetry server |
| **`cadre-web`** | Static Svelte 5 web cockpit and local telemetry UI |
| **`goose-cli`**, **`buzz-agent`**, **`pi-acp`**, **`amp-acp`** | Supported Agent Client Protocol (ACP) harnesses (`amp-acp` via overlay, unfree) |
| **`mesh-llm`** (`mesh-llm-cuda`, `mesh-llm-rocm`) | Distributed LLM inference over peer-to-peer mesh |
| **`buzz-app`**, **`buzz-cli`**, **`buzz-relay`**, **`buzz-acp`** | Self-hosted Nostr team chat, relay (`nixosModules.buzz-relay`), and ACP bridge |
| **`berd`** | Native desktop workspace for local Goose agents |
| **`block-review`**, **`ai-rules`**, **`braindump`** | Local git diff reviewer (`review`), cross-agent rule manager, and session exporter |

---

## License

MIT © [kleinbem](https://github.com/kleinbem)
