# The stack's packages on top of nixpkgs, for the NixOS module and anyone who
# wants them in their own pkgs. Prefers nix-packages (including pinned nixpkgs
# PRs) over nixpkgs so ahead-of-tree fixes are dogfooded until merged upstream.
inputs: final: prev:
let
  upstream = inputs.nix-packages.overlays.default final prev;
  pick = name: upstream.${name} or prev.${name};
in
{
  mesh-llm = pick "mesh-llm";
  mesh-llm-cuda = pick "mesh-llm-cuda";
  mesh-llm-rocm = pick "mesh-llm-rocm";
  buzz-app = pick "buzz-app";
  buzz-cli = pick "buzz-cli";
  buzz-relay = pick "buzz-relay";
  buzz-acp = pick "buzz-acp";
  buzz-agent = pick "buzz-agent";
  pi-acp = pick "pi-acp";
  amp-acp = pick "amp-acp";
  berd = pick "berd";
  block-review = pick "block-review";
  ai-rules = pick "ai-rules";
  braindump = pick "braindump";
  cadre-ai = final.callPackage ./package.nix { };
  cadre = final.cadre-ai;
  cadre-web = final.cadre-ai.web;
}
