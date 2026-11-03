# The stack's packages on top of nixpkgs, for the NixOS module and anyone who
# wants them in their own pkgs.
inputs: final: prev:
let
  upstream = inputs.nix-packages.overlays.default final prev;
in
{
  inherit (upstream)
    mesh-llm
    mesh-llm-cuda
    mesh-llm-rocm
    buzz-app
    buzz-cli
    buzz-relay
    buzz-acp
    ;
  cadre = final.callPackage ./pkgs/cadre { };
  mesh-agents = final.cadre;
}
