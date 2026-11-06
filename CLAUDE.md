# cadre

Public product repo: private, autonomous AI teammates directly onto your machines and into your team channels. The
README is the pitch; keep it short and true, and update it with every
user-visible change.

| Path | What lives here |
|---|---|
| `flake.nix` | Packages (the stack, re-exported), `nixosModules.default`, `homeManagerModules.default`, `overlays.default`, checks, treefmt. |
| `pkgs/cadre/` | The `nix run` launcher: starts or connects to MeshLLM or Ollama backend for Goose and Berd, or launches Buzz client directly. |
| `modules/nixos/` | `services.cadre` and Buzz ACP agent configurations. |
| `modules/home-manager/` | `services.cadre` user service: systemd on Linux, launchd on macOS. |
| `tests/` | The NixOS module on a minimal system, the home-manager module in a user's configuration; `push-cache.sh` runs the cache push against a throwaway SeaweedFS S3 (CI job `push-cache`). |

- Packages come from `kleinbem/nix-packages` for now; moving the Block AI ones
  here (and nix-packages consuming this flake) is the next step.
- Never default to `--auto` or `--publish`: the node stays private unless the
  user joins it with their own invite token.
- `nix flake check` and `nix fmt -- --fail-on-change` are the CI `check` job.
