{ lib
, buildNpmPackage
, nodejsCurrent
}:

(buildNpmPackage.override { nodejs = nodejsCurrent; }) {
  pname = "nix-me-tui";
  version = "1.0.0";

  src = lib.cleanSourceWith {
    src = ../../apps/post-install-tui;
    filter = path: type:
      let name = baseNameOf path;
      in name != "node_modules" && name != "dist" && name != ".git";
  };

  npmDepsHash = "sha256-yTyeGaeqAAGUA82eUJiRM7pop6FfyhPzmGWBIIOLHUw=";
  npmBuildScript = "build";

  installPhase = ''
    runHook preInstall
    substituteInPlace dist/index.js \
      --replace-fail '#!/usr/bin/env node' '#!${nodejsCurrent}/bin/node'
    install -Dm755 dist/index.js "$out/bin/nix-me-tui"
    install -Dm644 dist/yoga.wasm "$out/bin/yoga.wasm"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    ${nodejsCurrent}/bin/node --check "$out/bin/nix-me-tui"
    test "$($out/bin/nix-me-tui --version)" = "nix-me-tui 1.0.0"
  '';

  meta = {
    description = "Terminal UI for the nix-me configuration manager";
    license = lib.licenses.mit;
    mainProgram = "nix-me-tui";
    platforms = lib.platforms.unix;
  };
}
