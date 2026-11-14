{
  description = "Private AI teammates on your own compute (Goose & ACP agents over MeshLLM and Ollama)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Ahead-of-nixpkgs packages and pinned nixpkgs PRs (mesh-llm #571722,
    # buzz-relay #574877, buzz-app #577918, berd #580616, pi-acp #584498,
    # amp-acp #584499, and Block agent tooling).
    nix-packages.url = "github:kleinbem/nix-packages";
    nix-packages.inputs.nixpkgs.follows = "nixpkgs";
    # Only for the home-manager module's check.
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [ inputs.treefmt-nix.flakeModule ];

      flake = {
        overlays.default = import ./overlay.nix inputs;

        nixosModules = {
          default = {
            imports = [
              inputs.nix-packages.nixosModules.mesh-llm
              ./modules/nixos/cadre.nix
              ./modules/nixos/buzz-agents.nix
            ];
            nixpkgs.overlays = [ inputs.self.overlays.default ];
          };
          cadre = inputs.self.nixosModules.default;
        }
        // (
          if inputs.nix-packages.nixosModules ? buzz-relay then
            { inherit (inputs.nix-packages.nixosModules) buzz-relay; }
          else
            { }
        );

        homeManagerModules = {
          default = import ./modules/home-manager/cadre.nix {
            inherit (inputs.self) packages;
          };
          cadre = inputs.self.homeManagerModules.default;
        };
      };

      perSystem =
        {
          lib,
          pkgs,
          system,
          ...
        }:
        let
          upstream = inputs.nix-packages.packages.${system};
          pick = name: upstream.${name} or pkgs.${name};
          isAvailable =
            name:
            upstream ? ${name} || (pkgs ? ${name} && lib.meta.availableOn { inherit system; } pkgs.${name});
          # Free redistributable stack (check.yaml pushes packages.<system> to cache.kleinbem.dev).
          stack = lib.filterAttrs (name: _: isAvailable name) {
            mesh-llm = null;
            buzz-app = null;
            buzz-cli = null;
            buzz-relay = null;
            buzz-acp = null;
            buzz-agent = null;
            pi-acp = null;
            berd = null;
            block-review = null;
            ai-rules = null;
            braindump = null;
          };
          cadre = pkgs.callPackage ./package.nix {
            mesh-llm = pick "mesh-llm";
          };
        in
        {
          packages = lib.mapAttrs (name: _: pick name) stack // {
            inherit cadre;
            cadre-ai = cadre;
            inherit (cadre) web;
            cadre-web = cadre.web;
            inherit (pkgs) goose-cli;
            default = cadre;
          };

          # Unfree optional harnesses stay out of `packages` so CI never uploads them to the public cache.
          legacyPackages = lib.optionalAttrs (upstream ? amp-acp) {
            inherit (upstream) amp-acp;
          };

          checks = {
            inherit (cadre.tests) cli;
          }
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            module = import ./tests/module.nix {
              inherit pkgs;
              module = inputs.self.nixosModules.default;
            };
            home-manager = import ./tests/home-manager.nix {
              inherit pkgs;
              inherit (inputs) home-manager;
              module = inputs.self.homeManagerModules.default;
            };
          };

          treefmt.programs = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            shellcheck.enable = true;
          };
        };
    };
}
