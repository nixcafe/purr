{
  pkgs,
  lib,
  namespace,
  ...
}:
{
  _type = "package";
  byName = true;
  inherit namespace;
  inherit (pkgs) system;
}
