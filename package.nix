{
  lib,
  stdenvNoCC,
  buildNpmPackage,
  makeBinaryWrapper,
  shellcheck,
  bash,
  bashNonInteractive,
  coreutils,
  curl,
  goose-cli,
  jq,
  mesh-llm ? null,
  python3,
  versionCheckHook,
  nix-update-script,
  runCommand,
}:

let
  version = "0.1.0";

  web = buildNpmPackage {
    pname = "cadre-ai-web";
    inherit version;

    src = lib.fileset.toSource {
      root = ./web;
      fileset = lib.fileset.unions [
        ./web/package.json
        ./web/package-lock.json
        ./web/tsconfig.json
        ./web/vite.config.ts
        ./web/src
        ./web/test
      ];
    };

    npmDepsHash = "sha256-xx2TGYYRMMJDG/NIAJ61/TRYkuINug9hTgCZb/MIiI0=";
    # pacote writes _cacache/tmp when unpacking git lockfile entries (@kleinbem/web-config).
    makeCacheWritable = true;

    strictDeps = true;
    __structuredAttrs = true;

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      npm run check
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r build/. "$out/"
      if grep -rq '/nix/store/' "$out"; then
        echo "Static web bundle leaked /nix/store references" >&2
        exit 1
      fi
      runHook postInstall
    '';

    meta = {
      description = "Web cockpit and local-inference telemetry assets for Cadre";
      homepage = "https://github.com/kleinbem-dev/cadre";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [ kleinbem ];
      platforms = lib.platforms.all;
    };
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cadre-ai";
  inherit version;

  src = lib.fileset.toSource {
    root = ./pkgs/cadre;
    fileset = lib.fileset.unions [
      ./pkgs/cadre/cadre.sh
      ./pkgs/cadre/server.py
    ];
  };

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    python3
    shellcheck
  ];

  buildInputs = [
    bashNonInteractive
    python3
  ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    shellcheck cadre.sh
    python3 -m py_compile server.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 server.py "$out/libexec/cadre/server.py"
    install -Dm755 cadre.sh "$out/bin/cadre"
    substituteInPlace "$out/bin/cadre" \
      --replace-fail "@version@" "${finalAttrs.version}" \
      --replace-fail "@serverPy@" "$out/libexec/cadre/server.py" \
      --replace-fail "@webDir@" "${web}"
    mkdir -p "$out/share/cadre"
    ln -s ${web} "$out/share/cadre/web"
    patchShebangs "$out/bin/cadre" "$out/libexec/cadre/server.py"
    wrapProgram "$out/bin/cadre" \
      --prefix PATH : "${
        lib.makeBinPath (
          [
            coreutils
            curl
            goose-cli
            jq
            python3
          ]
          ++ lib.optional (mesh-llm != null) mesh-llm
        )
      }"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    inherit web;
    updateScript = nix-update-script { };
    tests.cli =
      runCommand "${finalAttrs.pname}-cli-check"
        {
          __darwinAllowLocalNetworking = true;
          nativeBuildInputs = [
            bash
            coreutils
            curl
            jq
            python3
          ];
        }
        ''
          bash ${./tests/cli.sh} ${lib.getExe finalAttrs.finalPackage} ${./pkgs/cadre/cadre.sh} ${./pkgs/cadre/server.py}
          touch "$out"
        '';
  };

  meta = {
    description = "Private AI teammates on your own compute (Goose over local inference)";
    homepage = "https://github.com/kleinbem-dev/cadre";
    changelog = "https://github.com/kleinbem-dev/cadre/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ kleinbem ];
    mainProgram = "cadre";
    platforms = if mesh-llm != null then mesh-llm.meta.platforms else lib.platforms.unix;
  };
})
