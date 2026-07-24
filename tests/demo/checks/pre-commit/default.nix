{
  pkgs,
  lib,
  namespace,
  ...
}:
pkgs.runCommand "pre-commit-check" { } "touch $out"
