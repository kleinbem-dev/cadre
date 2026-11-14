# cadre

Public product repo: private, autonomous AI teammates directly onto your machines and into your team channels. The
README is the pitch; keep it short and true, and update it with every
user-visible change.

| Path | What lives here |
|---|---|
| `flake.nix` | Packages (the stack, re-exported), `nixosModules.default`, `homeManagerModules.default`, `overlays.default`, checks, treefmt. |
| `package.nix` | `nixpkgs`-ready `cadre-ai` package (`mainProgram = "cadre"`, `passthru.web`, `passthru.tests.cli`, `nix-update-script`). |
| `pkgs/cadre/` | `cadre.sh` launcher and stdlib `server.py` static SPA + local-inference status/chat server. |
| `web/` | Svelte 5 + Tailwind CSS 4 web cockpit (`@kleinbem/web-config`) and `node --test` + `svelte-check` suite. |
| `modules/nixos/` | `services.cadre` and Buzz ACP agent configurations. |
| `modules/home-manager/` | `services.cadre` user service: systemd on Linux, launchd on macOS. |
| `tests/` | CLI/HTTP integration test (`cli.sh`), NixOS module check (`module.nix`), Home Manager check (`home-manager.nix`), and `push-cache.sh`. |

- Packages come from `kleinbem/nix-packages` for now; moving the Block AI ones
  here (and nix-packages consuming this flake) is the next step.
- Never default to `--auto` or `--publish`: the node stays private unless the
  user joins it with their own invite token.
- `nix flake check` and `nix fmt -- --fail-on-change` are the CI `check` job.
