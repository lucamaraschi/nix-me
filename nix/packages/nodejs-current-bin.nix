{ lib
, stdenv
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, python3
}:

let
  version = "26.11.1";
  archives = {
    "aarch64-darwin" = {
      platform = "darwin-arm64";
      hash = "sha256-Dvm0QwAGgb/8Bi7BJtU/l5M+qbCG6nPcugSA2H5jmzk=";
    };
    "x86_64-darwin" = {
      platform = "darwin-x64";
      hash = "sha256-aKik3gxG5pOiYdE++0PQQfzXOGGHgW75pLFL9gADrbI=";
    };
    "aarch64-linux" = {
      platform = "linux-arm64";
      hash = "sha256-CUXizeaqD1TZgPA4dN/lzzpUnOcUx/uQGeWRzgrM8oI=";
    };
    "x86_64-linux" = {
      platform = "linux-x64";
      hash = "sha256-OIO/xz+aaAyk6rBLGWBoqqqxNz/6d9j8GkQIIiSVtlE=";
    };
  };
  archive = archives.${stdenv.hostPlatform.system}
    or (throw "Node.js ${version} is unavailable for ${stdenv.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "nodejs-current-bin";
  inherit version;

  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-${archive.platform}.tar.xz";
    inherit (archive) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R bin include lib share "$out/"
    runHook postInstall
  '';

  postFixup = ''
    PATH="$out/bin:$PATH" patchShebangs "$out/bin" "$out/lib"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test "$($out/bin/node --version)" = "v${version}"
    $out/bin/npm --version >/dev/null
  '';

  passthru.python = python3;

  meta = {
    description = "Node.js current release binary distribution";
    homepage = "https://nodejs.org/";
    license = lib.licenses.mit;
    mainProgram = "node";
    platforms = builtins.attrNames archives;
  };
}
