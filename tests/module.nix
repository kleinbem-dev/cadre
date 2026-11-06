# The module on a minimal NixOS system: it evaluates, and the system with the
# MeshLLM unit and the agent tools builds.
{ pkgs, module }:

let
  nixos = pkgs.nixos {
    imports = [ module ];
    services.cadre = {
      enable = true;
      models = [ "Qwen3-8B-Q4_K_M" ];
      joinFile = "/run/secrets/cadre-join";
      buzz.agents.helper = {
        relayUrl = "wss://buzz.example.com";
        privateKeyFile = "/run/secrets/buzz-helper-key";
      };
    };
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };
  unit = nixos.config.systemd.units."mesh-llm.service".unit;
  buzzUnit = nixos.config.systemd.units."cadre-buzz-helper.service".unit;

  nixosOllama = pkgs.nixos {
    imports = [ module ];
    services.mesh-agents = {
      enable = true;
      backend = "ollama";
      models = [ "qwen2.5-coder" ];
    };
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };
in
pkgs.runCommand "cadre-module" { } ''
  grep -q -- '--join-file %d/join' ${unit}/mesh-llm.service
  grep -q 'LoadCredential=join:/run/secrets/cadre-join' ${unit}/mesh-llm.service
  grep -q 'BUZZ_RELAY_URL=wss://buzz.example.com' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'LoadCredential=key:/run/secrets/buzz-helper-key' ${buzzUnit}/cadre-buzz-helper.service
  test -x ${nixos.config.system.path}/bin/cadre
  test -x ${nixos.config.system.path}/bin/goose
  grep -q GOOSE_TELEMETRY_OFF ${nixos.config.system.build.setEnvironment}

  # Ollama backend: enables services.ollama, no mesh-llm unit
  test "${if nixosOllama.config.services.ollama.enable then "1" else "0"}" = "1"
  test "${if (nixosOllama.config.services.mesh-llm.enable or false) then "1" else "0"}" = "0"
  touch $out
''
