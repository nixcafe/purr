{
  pkgs,
  system,
  lib,
  ...
}:
if system == "x86_64-linux" then "tests-pass" else null
