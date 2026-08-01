{
  pkgs,
  lib,
  namespace,
  ...
}:
{
  type = "app";
  program = "${pkgs.hello}/bin/hello";
}
