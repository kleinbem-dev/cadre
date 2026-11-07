{
  lib,
  writeShellApplication,
  curl,
  goose-cli,
  jq,
  mesh-llm,
  python3,
  web ? null,
}:

(writeShellApplication {
  name = "cadre";
  runtimeInputs = [
    curl
    goose-cli
    jq
    mesh-llm
    python3
  ];
  text = builtins.readFile ./cadre.sh;
  meta = {
    description = "Private AI teammates on your own compute (Goose over local inference)";
    homepage = "https://github.com/kleinbem-dev/cadre";
    license = lib.licenses.mit;
    mainProgram = "cadre";
    inherit (mesh-llm.meta) platforms;
  };
}).overrideAttrs (old: lib.optionalAttrs (web != null) {
  buildCommand = old.buildCommand + ''
    mkdir -p $out/share/cadre/web
    cp -r ${web}/* $out/share/cadre/web/
  '';
})
