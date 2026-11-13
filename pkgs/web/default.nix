{ lib, buildNpmPackage }:

buildNpmPackage {
  pname = "cadre-web";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../../web;
    fileset = lib.fileset.unions [
      ../../web/package.json
      ../../web/package-lock.json
      ../../web/tsconfig.json
      ../../web/vite.config.ts
      ../../web/src
    ];
  };

  npmDepsHash = "sha256-p9g5ZrIvC6Hr7Ni0j2Zv137/aoHM2wD7XgWztPOBZbc=";
  # pacote writes _cacache/tmp when unpacking git lockfile entries.
  makeCacheWritable = true;

  strictDeps = true;
  __structuredAttrs = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm run check
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r build/* "$out/"
    runHook postInstall
  '';
}
