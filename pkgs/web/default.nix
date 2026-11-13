{ buildNpmPackage, importNpmLock }:

buildNpmPackage {
  pname = "cadre-web";
  version = "0.1.0";
  src = ../../web;
  npmDeps = importNpmLock { npmRoot = ../../web; };
  inherit (importNpmLock) npmConfigHook;
  installPhase = ''
    mkdir -p $out
    cp -r build/* $out/
  '';
}
