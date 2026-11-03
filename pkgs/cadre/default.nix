{
  lib,
  writeShellApplication,
  curl,
  goose-cli,
  jq,
  mesh-llm,
}:

writeShellApplication {
  name = "cadre";
  runtimeInputs = [
    curl
    goose-cli
    jq
    mesh-llm
  ];
  text = builtins.readFile ./cadre.sh;
  meta = {
    description = "Private AI teammates on your own compute (Goose over local inference)";
    homepage = "https://github.com/kleinbem/cadre";
    license = lib.licenses.mit;
    mainProgram = "cadre";
    inherit (mesh-llm.meta) platforms;
  };
}
