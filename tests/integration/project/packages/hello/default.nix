{
  pkgs,
  lib,
  namespace,
  ...
}:
{
  _type = "package";
  name = "hello";
  inherit namespace;
  libHasNs = lib ? "demo";
  inherit (pkgs) system;
  upper = lib.${namespace}.strings.upper.upper "abc";
}
