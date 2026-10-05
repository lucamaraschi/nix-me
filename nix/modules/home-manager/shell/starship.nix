# modules/home-manager/shell/starship.nix
# Starship prompt configuration via home-manager
{ ... }:

{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      nodejs.disabled = true;
      swift.disabled = true;
    };
  };
}
