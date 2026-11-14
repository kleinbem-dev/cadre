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
Powered by [Goose](https://github.com/aaif-goose/goose) over ACP, and backed by your choice of local compute—whether a single [Ollama](https://ollama.ai) instance on your laptop or a distributed [MeshLLM](https://github.com/Mesh-LLM/mesh-llm) cluster split across your GPU boxes.

No cloud API keys required. No telemetry. Inference runs entirely on your hardware (Buzz agents talk only to your configured relays and whatever network resources their tools access).

```bash
nix run github:kleinbem-dev/cadre
```

---

## What It Does

1. **In Team Chat:** An autonomous member of your [Buzz](https://github.com/block/buzz) relays (via ACP agent harnesses). Team members `@cadre` in channels to debug code, explain regressions, or run commands (defaults to owner-only authorization; configure `respondTo` for team allowlists or open channels).
2. **In Your Terminal:** An interactive pairing assistant (`cadre` / `goose`) that plans, runs shell commands, navigates code, and edits files.
3. **Flexible Compute:** Switch between **Ollama** or **MeshLLM** with a single flag. If you have multiple devices, MeshLLM splits models too large for one machine across your fleet.

---

## Architecture & Compute Backends

```text
               ┌────────────────────────────────────────────────────────────────────────────────────────┐
               │                                        SURFACES                                        │
               │  Terminal (cadre)  │  Web Dashboard (cadre web)  │  Desktop (cadre gui)  │  Chat (cadre)│
               └───────────────────────────────────────────┬────────────────────────────────────────────┘
                                   │  ACP (Agent Client Protocol)
                                   ▼
               ┌────────────────────────────────────────────────────────┐
               │                        CADRE                           │
               │     Autonomous Agent Engine (aaif-goose + ACP)         │
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

The `gui` and `chat` commands need `berd` and `buzz-app` (or `buzz-cli`) on `PATH`. The `cadre` package does not include heavy desktop applications by default. Make them available in your environment or install them via `services.cadre.desktop.enable`.

```bash
# Terminal pairing assistant (Goose in CLI):
nix run github:kleinbem-dev/cadre

# Web Dashboard (SvelteKit + local inference telemetry & chat):
nix run github:kleinbem-dev/cadre -- web

# Desktop GUI (Berd window on your local backend):
nix run github:kleinbem-dev/cadre -- gui

# Team Chat (Buzz client):
nix run github:kleinbem-dev/cadre -- chat

# Print CLI version:
nix run github:kleinbem-dev/cadre -- --version

# Explicitly use Ollama backend:
nix run github:kleinbem-dev/cadre -- --backend ollama --model qwen2.5-coder

# Explicitly use MeshLLM backend:
nix run github:kleinbem-dev/cadre -- --backend mesh --model Qwen3-8B-Q4_K_M
```

---

## Fleet Setup (NixOS)

Run `cadre` as a system service on your machines:

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
            desktop.enable = true; # installs Berd GUI and Buzz chat alongside CLI
            backend = "mesh"; # or "ollama"
            models = [ "Qwen3-14B-Q4_K_M" ];
            # package = pkgs.mesh-llm-cuda;  # NVIDIA acceleration

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
    desktop.enable = true; # adds Cadre (Berd) and Cadre (Buzz) menu entries on Linux
    backend = "mesh";
    models = [ "Qwen3-8B-Q4_K_M" ];
  };
}
```

---

## Ecosystem Packages

`cadre` packages the self-hosted AI agent stack for Nix:

| Package | Purpose |
| :--- | :--- |
| **`cadre`** / **`cadre-ai`** | The unified launcher, local telemetry server, and agent harness |
| **`cadre-web`** | The static web surface and telemetry cockpit for Cadre |
| **`goose-cli`** | The core autonomous agent runtime ([aaif-goose](https://github.com/aaif-goose/goose)) |
| **`mesh-llm`**, **`skippy`** | Distributed LLM inference over peer-to-peer mesh |
| **`buzz-app`**, **`buzz-cli`**, **`buzz-relay`**, **`buzz-acp`** | Self-hosted Nostr team chat where agents are full participants |
| **`berd`**, **`braindump`** | Native desktop UI and knowledge tools |

---

## License

MIT © [kleinbem](https://github.com/kleinbem)
