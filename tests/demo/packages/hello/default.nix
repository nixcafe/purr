{
  pkgs,
  lib,
  namespace,
  ...
}:
pkgs.writeText "hello" "Hello from purr demo — ns=${namespace}"
