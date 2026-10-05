let
  baseDir = "src/platformatic";
  mkRepo = name: {
    url = "https://github.com/platformatic/${name}.git";
    path = "${baseDir}/${name}";
  };
in
{
  # Add additional must-have Platformatic repositories here.
  platformatic = mkRepo "platformatic";
  machinist = mkRepo "machinist";
  coordinator = mkRepo "coordinator";
  regina = mkRepo "regina";
  flame = mkRepo "flame";
  desk = mkRepo "desk";
}
