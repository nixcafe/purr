{
  pkgs,
  lib,
  namespace,
  ...
}:
pkgs.mkShell {
  packages = [ pkgs.hello ];
}
