# modules/home-manager/shell/starship.nix
# Starship prompt configuration via home-manager
{ ... }:

{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      swift.disabled = true;
    };
  };
}
