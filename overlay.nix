# The stack's packages on top of nixpkgs, for the NixOS module and anyone who
# wants them in their own pkgs. Upstream-first: prefers nixpkgs attributes if
# already present, falling back to nix-packages overlay.
inputs: final: prev:
let
  upstream = inputs.nix-packages.overlays.default final prev;
  pick = name: prev.${name} or upstream.${name};
in
{
  mesh-llm = pick "mesh-llm";
  mesh-llm-cuda = pick "mesh-llm-cuda";
  mesh-llm-rocm = pick "mesh-llm-rocm";
  skippy = pick "skippy";
  buzz-app = pick "buzz-app";
  buzz-cli = pick "buzz-cli";
  buzz-relay = pick "buzz-relay";
  buzz-acp = pick "buzz-acp";
  berd = pick "berd";
  braindump = pick "braindump";
  cadre = final.callPackage ./pkgs/cadre { };
  mesh-agents = final.cadre;
}
