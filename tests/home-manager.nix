# The home-manager module in a user's configuration: the user service and the
# agent tools build.
{
  pkgs,
  home-manager,
  module,
}:

let
  home = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
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
          models = [ "Qwen3-8B-Q4_K_M" ];
          joinFile = "/run/user/1000/cadre-join";
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
        services.mesh-agents = {
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
  grep -q 'Qwen3-8B-Q4_K_M' $(grep -o '/nix/store/[^ ]*mesh-llm-config.toml' $node)
  test -x ${files}/home-path/bin/cadre
  test -x ${files}/home-path/bin/goose
  grep -q "GOOSE_TELEMETRY_OFF=\"1\"" ${files}/home-path/etc/profile.d/hm-session-vars.sh

  # Ollama backend: enables ollama service via alias, no mesh-llm unit
  ollamaUnit=${filesOllama}/home-files/.config/systemd/user/ollama.service
  test -f $ollamaUnit
  grep -q 'WantedBy=default.target' $ollamaUnit
  test ! -f ${filesOllama}/home-files/.config/systemd/user/mesh-llm.service
  test -x ${filesOllama}/home-path/bin/cadre

  # Ollama backend with autoStart = false: unit exists without WantedBy
  ollamaNoAutoUnit=${filesOllamaNoAutoStart}/home-files/.config/systemd/user/ollama.service
  test -f $ollamaNoAutoUnit
  if grep -q 'WantedBy=' $ollamaNoAutoUnit; then
    echo "Expected no WantedBy in ollama service when autoStart is false" >&2
    exit 1
  fi

  touch $out
''
