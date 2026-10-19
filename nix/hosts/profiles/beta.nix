# Opt-in profile for beta application-state management.
{ ... }:

{
  projects.settingsProfiles = [ "beta" ];

  apps.state = {
    enable = true;
    settingsProfiles = [ "beta" ];
  };
}
