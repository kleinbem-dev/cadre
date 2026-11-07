{
  description = "Private AI teammates on your own compute (Goose over local inference: Ollama, MeshLLM)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # The packages until they land in nixpkgs: mesh-llm and skippy
    # (NixOS/nixpkgs#571722), the Buzz suite, Berd and friends.
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
        };

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
          pick = name: pkgs.${name} or upstream.${name};
          # The agent stack, as far as it builds on this system.
          stack = lib.filterAttrs (name: _: pkgs ? ${name} || upstream ? ${name}) {
            mesh-llm = null;
            skippy = null;
            buzz-app = null;
            buzz-cli = null;
            buzz-relay = null;
            buzz-acp = null;
            berd = null;
            braindump = null;
          };
          cadre = pkgs.callPackage ./pkgs/cadre {
            mesh-llm = pick "mesh-llm";
          };
          web = pkgs.buildNpmPackage {
            pname = "cadre-web";
            version = "0.1.0";
            src = ./web;
            npmDeps = pkgs.importNpmLock { npmRoot = ./web; };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;
            installPhase = ''
              mkdir -p $out
              cp -r build/* $out/
            '';
          };
        in
        {
          packages = lib.mapAttrs (name: _: pick name) stack // {
            inherit cadre web;
            inherit (pkgs) goose-cli;
            default = cadre;
          };

          checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
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
