{ pkgs, ... }:

let
  activationRunner = pkgs.runCommand "nix-me-activate-system" { } ''
    install -m 0555 ${../../../packages/management-api/bin/nix-me-activate-system} "$out"
  '';
in
{
  # The installer executes this immutable helper after the system build. It
  # owns the short-lived authorization required by nested Homebrew/mas sudo.
  environment.etc."nix-me/activate-system".source = activationRunner;
}
