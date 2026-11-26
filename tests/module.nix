# The module on a minimal NixOS system: it evaluates, and the system with the
# MeshLLM unit, declarative teammates, and ACP agent harnesses builds.
{ pkgs, module }:

let
  # Stub external C++/Rust/Go binaries (evaluated in `packages.*`) so headless module checks stay fast on CI runners.
  stubOverlay = final: _prev: {
    mesh-llm = (final.writeShellScriptBin "mesh-llm" "exit 0").overrideAttrs {
      meta = {
        mainProgram = "mesh-llm";
        platforms = final.lib.platforms.unix;
      };
    };
    berd = final.writeShellScriptBin "berd" "exit 0";
    buzz-app = final.writeShellScriptBin "buzz-app" "exit 0";
    buzz-cli = final.writeShellScriptBin "buzz" "exit 0";
    buzz-acp = final.writeShellScriptBin "buzz-acp" "exit 0";
    buzz-agent = final.writeShellScriptBin "buzz-agent" "exit 0";
    amp-acp = final.writeShellScriptBin "amp-acp" "exit 0";
    block-review = final.writeShellScriptBin "review" "exit 0";
    ai-rules = final.writeShellScriptBin "ai-rules" "exit 0";
    braindump = final.writeShellScriptBin "braindump" "exit 0";
  };

  nixos = pkgs.nixos {
    imports = [ module ];
    nixpkgs.overlays = [ stubOverlay ];
    services.cadre = {
      enable = true;
      models = [ "Qwen3-8B-Q4_K_M" ];
      joinFile = "/run/secrets/cadre-join";
      extraArgs = [ "--test-extra-arg" ];
      tools.enable = true;
      desktop.enable = true;
      agents = {
        reviewer = {
          name = "Cadre Reviewer";
          role = "Security & Diff Auditor";
          harness = "pi-acp";
          model = "Qwen3-Reviewer";
          systemPrompt = "Check every diff for regressions.";
          tools = [
            "git"
            "review"
          ];
        };
        autoHelper = {
          name = "Auto Helper";
        };
      };
      web = {
        enable = true;
        port = 8384;
        openFirewall = true;
        enableChatProxy = true;
      };
      buzz.agents = {
        helper = {
          relayUrl = "wss://buzz.example.com";
          privateKeyFile = "/run/secrets/buzz-helper-key";
          respondTo = "allowlist";
          owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
          allowlist = [ "deadbeef" ];
        };
        piBot = {
          relayUrl = "wss://buzz.example.com";
          privateKeyFile = "/run/secrets/buzz-pi-key";
          harness = "pi-acp";
          sessionPolicy = "thread";
          systemPrompt = "Answer concisely in threads.";
          respondTo = "owner-only";
          owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        };
        nativeBot = {
          relayUrl = "wss://buzz.example.com";
          privateKeyFile = "/run/secrets/buzz-native-key";
          harness = "buzz-agent";
          respondTo = "owner-only";
          owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        };
        ampBot = {
          relayUrl = "wss://buzz.example.com";
          privateKeyFile = "/run/secrets/buzz-amp-key";
          environmentFile = "/run/secrets/buzz-amp.env";
          harness = "amp-acp";
          respondTo = "owner-only";
          owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        };
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
  unit = nixos.config.systemd.units."mesh-llm.service".unit;
  buzzUnit = nixos.config.systemd.units."cadre-buzz-helper.service".unit;
  piUnit = nixos.config.systemd.units."cadre-buzz-piBot.service".unit;
  nativeUnit = nixos.config.systemd.units."cadre-buzz-nativeBot.service".unit;
  ampUnit = nixos.config.systemd.units."cadre-buzz-ampBot.service".unit;
  webUnit = nixos.config.systemd.units."cadre-web.service".unit;
  agentsEtc = nixos.config.environment.etc."cadre/agents.json".source;

  nixosMissingAmpEnv = pkgs.nixos {
    imports = [ module ];
    nixpkgs.overlays = [ stubOverlay ];
    services.cadre = {
      enable = true;
      buzz.agents.badAmp = {
        relayUrl = "wss://buzz.example.com";
        privateKeyFile = "/run/secrets/buzz-amp-key";
        harness = "amp-acp";
        owner = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
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

  nixosOwnerWarning = pkgs.nixos {
    imports = [ module ];
    nixpkgs.overlays = [ stubOverlay ];
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
    nixpkgs.overlays = [ stubOverlay ];
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
  grep -q 'BUZZ_ACP_AGENT_COMMAND=goose' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_AGENT_ARGS=acp' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_RESPOND_TO=allowlist' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_AGENT_OWNER=3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'BUZZ_ACP_RESPOND_TO_ALLOWLIST=deadbeef' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'LoadCredential=key:/run/secrets/buzz-helper-key' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'SystemCallFilter=@system-service' ${buzzUnit}/cadre-buzz-helper.service
  grep -q 'UMask=0077' ${buzzUnit}/cadre-buzz-helper.service

  # Non-goose ACP adapters: zero-arg stdio launch, Pi provider/settings files, Amp EnvironmentFile, and buzz-agent local OpenAI wiring
  grep -q 'BUZZ_ACP_AGENT_COMMAND=pi-acp' ${piUnit}/cadre-buzz-piBot.service
  grep -q 'Environment="BUZZ_ACP_AGENT_ARGS="' ${piUnit}/cadre-buzz-piBot.service
  grep -q 'BUZZ_ACP_MODEL=cadre/cadre' ${piUnit}/cadre-buzz-piBot.service
  grep -q 'BUZZ_ACP_SESSION_POLICY=thread' ${piUnit}/cadre-buzz-piBot.service
  grep -q 'BUZZ_ACP_SYSTEM_PROMPT_FILE=' ${piUnit}/cadre-buzz-piBot.service
  piStart=$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' ${piUnit}/cadre-buzz-piBot.service)
  grep -q '\.pi/agent/models\.json' "$piStart"
  grep -q '\.pi/agent/settings\.json' "$piStart"
  grep -Eq '"openai-completions"' $(grep -o '/nix/store/[^ ]*pi-models.json' "$piStart")
  grep -Eq '"defaultProvider": *"cadre"' $(grep -o '/nix/store/[^ ]*pi-settings.json' "$piStart")

  grep -q 'BUZZ_ACP_AGENT_COMMAND=buzz-agent' ${nativeUnit}/cadre-buzz-nativeBot.service
  grep -q 'BUZZ_AGENT_PROVIDER=openai' ${nativeUnit}/cadre-buzz-nativeBot.service
  grep -q 'OPENAI_COMPAT_BASE_URL=http://127.0.0.1:9337/v1' ${nativeUnit}/cadre-buzz-nativeBot.service
  grep -q 'OPENAI_COMPAT_API=chat' ${nativeUnit}/cadre-buzz-nativeBot.service

  grep -q 'BUZZ_ACP_AGENT_COMMAND=amp-acp' ${ampUnit}/cadre-buzz-ampBot.service
  grep -q 'Environment="BUZZ_ACP_AGENT_ARGS="' ${ampUnit}/cadre-buzz-ampBot.service
  grep -q 'EnvironmentFile=/run/secrets/buzz-amp.env' ${ampUnit}/cadre-buzz-ampBot.service

  grep -q 'server.py' ${webUnit}/cadre-web.service
  grep -q '8384' ${webUnit}/cadre-web.service
  grep -q -- '--agents-file=' ${webUnit}/cadre-web.service
  grep -q -- '--enable-chat-proxy' ${webUnit}/cadre-web.service
  grep -q 'DynamicUser=true' ${webUnit}/cadre-web.service
  grep -q 'UMask=0077' ${webUnit}/cadre-web.service

  grep -Eq '"handle": *"@reviewer"' ${agentsEtc}
  grep -Eq '"harness": *"pi-acp"' ${agentsEtc}
  grep -Eq '"model": *"Qwen3-Reviewer"' ${agentsEtc}
  grep -Eq '"model": *""' ${agentsEtc}

  test "${
    if
      builtins.any (
        a: !a.assertion && pkgs.lib.hasInfix "environmentFile" a.message
      ) nixosMissingAmpEnv.config.assertions
    then
      "1"
    else
      "0"
  }" = "1"

  test "${
    if (builtins.elem 8384 nixos.config.networking.firewall.allowedTCPPorts) then "1" else "0"
  }" = "1"
  test "${if nixos.config.warnings == [ ] then "1" else "0"}" = "1"
  test "${if nixosOwnerWarning.config.warnings != [ ] then "1" else "0"}" = "1"
  test -x ${nixos.config.system.path}/bin/cadre
  test "$(${nixos.config.system.path}/bin/cadre --version)" = "cadre 0.1.0"
  test -x ${nixos.config.system.path}/bin/goose
  test -x ${nixos.config.system.path}/bin/pi-acp
  test -x ${nixos.config.system.path}/bin/review
  test -x ${nixos.config.system.path}/bin/braindump
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
