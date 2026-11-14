# The module on a minimal NixOS system: it evaluates, and the system with the
# MeshLLM unit and the agent tools builds.
{ pkgs, module }:

let
  nixos = pkgs.nixos {
    imports = [ module ];
    nixpkgs.overlays = [
      # WORKAROUND(berd): locked kleinbem/nix-packages pins berd 0.6.4 without aws-lc in buildInputs (updated in https://github.com/NixOS/nixpkgs/pull/580616) — remove when flake.lock includes berd >= 0.6.5.
      (final: _prev: {
        berd = final.writeShellScriptBin "berd" "exit 0";
        buzz-app = final.writeShellScriptBin "buzz-app" "exit 0";
      })
    ];
    services.cadre = {
      enable = true;
      models = [ "Qwen3-8B-Q4_K_M" ];
      joinFile = "/run/secrets/cadre-join";
      extraArgs = [ "--test-extra-arg" ];
      web = {
        enable = true;
        port = 8384;
        openFirewall = true;
        enableChatProxy = true;
      };
      buzz.agents.helper = {
        relayUrl = "wss://buzz.example.com";
        privateKeyFile = "/run/secrets/buzz-helper-key";
        respondTo = "allowlist";
        owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        allowlist = [ "deadbeef" ];
      };
      desktop.enable = true;
    };
    boot.loader.grub.enable = false;
    documentation.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };
  unit = nixos.config.systemd.units."mesh-llm.service".unit;
  buzzUnit = nixos.config.systemd.units."cadre-buzz-helper.service".unit;
  webUnit = nixos.config.systemd.units."cadre-web.service".unit;

  nixosOwnerWarning = pkgs.nixos {
    imports = [ module ];
    services.cadre = {
      enable = true;
      buzz.agents.silent = {
        relayUrl = "wss://buzz.example.com";
        privateKeyFile = "/run/secrets/buzz-silent-key";
      };
    };
    boot.loader.grub.enable = false;
    documentation.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };

  nixosNoAuto = pkgs.nixos {
    imports = [ module ];
    services.cadre = {
      enable = true;
      autoStart = false;
    };
    boot.loader.grub.enable = false;
    documentation.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };
  noAutoUnit = nixosNoAuto.config.systemd.units."mesh-llm.service".unit;

  nixosOllama = pkgs.nixos {
    imports = [ module ];
    services.cadre = {
      enable = true;
      backend = "ollama";
      models = [ "qwen2.5-coder" ];
    };
    boot.loader.grub.enable = false;
    documentation.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };

  nixosOllamaNoAuto = pkgs.nixos {
    imports = [ module ];
    services.cadre = {
      enable = true;
      backend = "ollama";
      models = [ "qwen2.5-coder" ];
      autoStart = false;
    };
    boot.loader.grub.enable = false;
    documentation.enable = false;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    system.stateVersion = "26.05";
  };
  ollamaNoAutoUnit = nixosOllamaNoAuto.config.systemd.units."ollama.service".unit;
  ollamaModelLoaderNoAutoUnit =
    nixosOllamaNoAuto.config.systemd.units."ollama-model-loader.service".unit;
in
pkgs.runCommand "cadre-module" { } ''
  grep -q -- '--join-file %d/join' ${unit}/mesh-llm.service
  grep -q 'LoadCredential=join:/run/secrets/cadre-join' ${unit}/mesh-llm.service
  grep -q -- '--test-extra-arg' ${unit}/mesh-llm.service
  grep -q 'WantedBy=multi-user.target' ${unit}/mesh-llm.service
  grep -q 'BUZZ_RELAY_URL=wss://buzz.example.com' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_RESPOND_TO=allowlist' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_AGENT_OWNER=3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_RESPOND_TO_ALLOWLIST=deadbeef' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'LoadCredential=key:/run/secrets/buzz-helper-key' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'SystemCallFilter=@system-service' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'UMask=0077' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'server.py' ${webUnit}/cadre-web.service
  grep -q '8384' ${webUnit}/cadre-web.service
  grep -q -- '--enable-chat-proxy' ${webUnit}/cadre-web.service
  grep -q 'DynamicUser=true' ${webUnit}/cadre-web.service
  grep -q 'UMask=0077' ${webUnit}/cadre-web.service
  test "${
    if (builtins.elem 8384 nixos.config.networking.firewall.allowedTCPPorts) then "1" else "0"
  }" = "1"
  test "${if nixos.config.warnings == [ ] then "1" else "0"}" = "1"
  test "${if nixosOwnerWarning.config.warnings != [ ] then "1" else "0"}" = "1"
  test -x ${nixos.config.system.path}/bin/cadre
  test "$(${nixos.config.system.path}/bin/cadre --version)" = "cadre 0.1.0"
  test -x ${nixos.config.system.path}/bin/goose
  test -x ${nixos.config.system.path}/bin/berd
  grep -q GOOSE_TELEMETRY_OFF ${nixos.config.system.build.setEnvironment}

  # autoStart = false: no WantedBy in unit
  if grep -q 'WantedBy=' ${noAutoUnit}/mesh-llm.service; then
    echo "Expected no WantedBy in mesh-llm service when autoStart is false" >&2
    exit 1
  fi

  # Ollama backend: enables services.ollama, no mesh-llm unit or mesh-llm binary in wrapper
  test "${if nixosOllama.config.services.ollama.enable then "1" else "0"}" = "1"
  test "${if (nixosOllama.config.services.mesh-llm.enable or false) then "1" else "0"}" = "0"
  if grep -q 'mesh-llm' ${nixosOllama.config.system.path}/bin/cadre; then
    echo "Expected Ollama-only cadre wrapper not to pull mesh-llm" >&2
    exit 1
  fi

  # Ollama backend with autoStart = false: no WantedBy in ollama or ollama-model-loader
  if grep -q 'WantedBy=' ${ollamaNoAutoUnit}/ollama.service; then
    echo "Expected no WantedBy in ollama service when autoStart is false" >&2
    exit 1
  fi
  if grep -q 'WantedBy=' ${ollamaModelLoaderNoAutoUnit}/ollama-model-loader.service; then
    echo "Expected no WantedBy in ollama-model-loader service when autoStart is false" >&2
    exit 1
  fi
  touch $out
''
