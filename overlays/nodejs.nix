final: prev:

{
  nodejs-22_14 = prev.nodejs.overrideAttrs (oldAttrs: rec {
    version = "22.14.0";
    src = prev.fetchurl {
      url = "https://nodejs.org/download/release/v${version}/node-v${version}.tar.xz";
      hash = "sha256-pzD3xdOc2o0V1vZ3iJ3zdC7uJKp2qHQNv0Bi9qp+NKY=";
    };
  });
}