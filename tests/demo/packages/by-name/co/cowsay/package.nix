{
  stdenv,
  pkgs,
  lib,
  ...
}:
pkgs.writeText "cowsay-by-name" "Hello from by-name package"
