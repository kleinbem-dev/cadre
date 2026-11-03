<p align="center">
  <img src="assets/logo.svg" alt="cadre banner" width="680" />
</p>

<p align="center">
  <a href="https://github.com/kleinbem/cadre/actions"><img src="https://img.shields.io/badge/CI-passing-success?style=flat-square" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License: MIT"></a>
  <a href="BRANDING.md"><img src="https://img.shields.io/badge/Identity-Cadre%20%E2%97%88-f59e0b?style=flat-square" alt="Branding"></a>
</p>

---

**`cadre`** brings private, autonomous AI teammates directly onto your machines and into your team channels. 
Powered by [Goose](https://github.com/aaif-goose/goose) over ACP, and backed by your choice of local compute—whether a single [Ollama](https://ollama.ai) instance on your laptop or a distributed [MeshLLM](https://github.com/Mesh-LLM/mesh-llm) cluster split across your GPU boxes.

No cloud API keys. No telemetry. Everything runs on your hardware.

```bash
nix run github:kleinbem-dev/cadre
```

---

## What It Does

1. **In Team Chat:** An autonomous member of your [Buzz](https://github.com/block/buzz) relays (via ACP agent harnesses). Team members `@cadre` in any channel to debug code, explain regressions, or run commands.
2. **In Your Terminal:** An interactive pairing assistant (`cadre` / `goose`) that plans, runs shell commands, navigates code, and edits files.
3. **Flexible Compute:** Switch between **Ollama** or **MeshLLM** with a single flag. If you have multiple devices, MeshLLM splits models too large for one machine across your fleet.

---

## Architecture & Compute Backends

```text
               ┌────────────────────────────────────────────────────────────────────────┐
               │                                SURFACES                                │
               │  Terminal (cadre)  │  Desktop GUI (cadre gui)  │  Team Chat (cadre chat)│
               └───────────────────────────────────┬────────────────────────────────────┘
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

```bash
# Terminal pairing assistant (Goose in CLI):
nix run github:kleinbem-dev/cadre

# Desktop GUI (Berd window on your local backend):
nix run github:kleinbem-dev/cadre -- gui

# Team Chat (Buzz client):
nix run github:kleinbem-dev/cadre -- chat

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
            desktop.enable = true; # installs Berd GUI and Buzz chat alongside CLI
            backend = "mesh"; # or "ollama"
            models = [ "Qwen3-14B-Q4_K_M" ];
            # package = pkgs.mesh-llm-cuda;  # NVIDIA acceleration

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
| **`cadre`** | The unified launcher and agent harness |
| **`goose-cli`** | The core autonomous agent runtime ([aaif-goose](https://github.com/aaif-goose/goose)) |
| **`mesh-llm`**, **`skippy`** | Distributed LLM inference over peer-to-peer mesh |
| **`buzz-app`**, **`buzz-cli`**, **`buzz-relay`**, **`buzz-acp`** | Self-hosted Nostr team chat where agents are full participants |
| **`berd`**, **`braindump`** | Native desktop UI and knowledge tools |

---

## License

MIT © [kleinbem](https://github.com/kleinbem)
