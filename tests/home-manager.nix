# The home-manager module in a user's configuration: the user service and the
# agent tools build.
{
  pkgs,
  home-manager,
  module,
}:

let
  # WORKAROUND(berd): locked kleinbem/nix-packages pins berd 0.6.4 without aws-lc in buildInputs — remove when flake.lock includes berd >= 0.6.5 (or keep to avoid compiling Tauri desktop apps in headless HM checks).
  testPkgs = pkgs.extend (
    final: _prev: {
      berd = final.writeShellScriptBin "berd" "exit 0";
      buzz-app = final.writeShellScriptBin "buzz-app" "exit 0";
    }
  );

  home = home-manager.lib.homeManagerConfiguration {
    pkgs = testPkgs;
    modules = [
      module
      {
        home = {
          username = "alice";
          homeDirectory = "/home/alice";
          stateVersion = "26.05";
        };
        services.cadre = {
          enable = true;
          desktop.enable = true;
          models = [ "Qwen3-8B-Q4_K_M" ];
          joinFile = "/run/user/1000/cadre-join";
          extraArgs = [ "--hm-extra-flag" ];
        };
      }
    ];
  };
  files = home.activationPackage;

  homeOllama = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      module
      {
        home = {
          username = "bob";
          homeDirectory = "/home/bob";
          stateVersion = "26.05";
        };
        services.cadre = {
          enable = true;
          backend = "ollama";
        };
      }
    ];
  };
  filesOllama = homeOllama.activationPackage;

  homeOllamaNoAutoStart = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      module
      {
        home = {
          username = "carol";
          homeDirectory = "/home/carol";
          stateVersion = "26.05";
        };
        services.cadre = {
          enable = true;
          backend = "ollama";
          autoStart = false;
        };
      }
    ];
  };
  filesOllamaNoAutoStart = homeOllamaNoAutoStart.activationPackage;
in
pkgs.runCommand "cadre-home-manager" { } ''
  unit=${files}/home-files/.config/systemd/user/mesh-llm.service
  grep -q 'WantedBy=default.target' $unit
  node=$(sed -n 's/^ExecStart=//p' $unit)
  grep -q -- '--join-file /run/user/1000/cadre-join' $node
  grep -q -- '--hm-extra-flag' $node
  grep -q 'Qwen3-8B-Q4_K_M' $(grep -o '/nix/store/[^ ]*mesh-llm-config.toml' $node)
  test -x ${files}/home-path/bin/cadre
  # Verify our `cadre` CLI is installed, never nixpkgs' Ruby gem `cadre-1.0.4`.
  test "$(${files}/home-path/bin/cadre --version)" = "cadre 0.1.0"
  test -x ${files}/home-path/bin/goose
  test -x ${files}/home-path/bin/berd
  test -f ${files}/home-path/share/applications/cadre-berd.desktop
  test -f ${files}/home-path/share/applications/cadre-buzz.desktop
  grep -q "GOOSE_TELEMETRY_OFF=\"1\"" ${files}/home-path/etc/profile.d/hm-session-vars.sh

  # Goose custom provider provisioned declaratively (mesh.json left to runtime writer)
  test -f ${files}/home-files/.config/goose/custom_providers/cadre.json
  grep -q '"name":"cadre"' ${files}/home-files/.config/goose/custom_providers/cadre.json
  test ! -f ${files}/home-files/.config/goose/custom_providers/mesh.json

  # Ollama backend: enables ollama service via alias, no mesh-llm unit or mesh-llm wrapper dep
  ollamaUnit=${filesOllama}/home-files/.config/systemd/user/ollama.service
  test -f $ollamaUnit
  grep -q 'WantedBy=default.target' $ollamaUnit
  test ! -f ${filesOllama}/home-files/.config/systemd/user/mesh-llm.service
  test -x ${filesOllama}/home-path/bin/cadre
  test "$(${filesOllama}/home-path/bin/cadre --version)" = "cadre 0.1.0"
  if grep -q 'mesh-llm' ${filesOllama}/home-path/bin/cadre; then
    echo "Expected Ollama-only HM cadre wrapper not to pull mesh-llm" >&2
    exit 1
  fi
  test -f ${filesOllama}/home-files/.config/goose/custom_providers/cadre.json
  grep -q '"name":"cadre"' ${filesOllama}/home-files/.config/goose/custom_providers/cadre.json
  grep -q '"context_limit":32768' ${filesOllama}/home-files/.config/goose/custom_providers/cadre.json
  test ! -f ${filesOllama}/home-files/.config/goose/custom_providers/mesh.json

  # Ollama backend with autoStart = false: unit exists without WantedBy
  ollamaNoAutoUnit=${filesOllamaNoAutoStart}/home-files/.config/systemd/user/ollama.service
  test -f $ollamaNoAutoUnit
  if grep -q 'WantedBy=' $ollamaNoAutoUnit; then
    echo "Expected no WantedBy in ollama service when autoStart is false" >&2
    exit 1
  fi

  touch $out
''
