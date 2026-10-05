let
  baseDir = "src/ai";
  mkRepo = name: url: {
    inherit url;
    path = "${baseDir}/${name}";
  };
in
{
  ds4 = mkRepo "ds4" "https://github.com/antirez/ds4.git";
  pi-ds4 = mkRepo "pi-ds4" "https://github.com/mitsuhiko/pi-ds4.git";
}
