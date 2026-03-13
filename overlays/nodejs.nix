final: prev:

{
  # Skip tests for nodejs_22 - network tests fail in nix sandbox
  nodejs_22 = prev.nodejs_22.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
}