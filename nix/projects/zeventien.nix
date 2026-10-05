let
  baseDir = "src/zeventien";
  mkRepo = name: {
    url = "git@github.com:zeventien/${name}.git";
    path = "${baseDir}/${name}";
  };
in
{
  # Add Zeventien repositories here as needed.
  # example = mkRepo "example";
}
