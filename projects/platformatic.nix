let
  baseDir = "src/platformatic";
  mkRepo = name: {
    url = "git@github.com:platformatic/${name}.git";
    path = "${baseDir}/${name}";
  };
in
{
  # Add additional must-have Platformatic repositories here.
  platformatic = mkRepo "platformatic";
  machinist = mkRepo "machinist";
  coordinator = mkRepo "coordinator";
}
