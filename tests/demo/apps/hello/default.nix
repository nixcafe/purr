{
  pkgs,
  lib,
  namespace,
  ...
}:
{
  type = "app";
  program = "${pkgs.cowsay}/bin/cowsay";
}
