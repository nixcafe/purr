{
  config,
  lib,
  namespace,
  purr,
  purrLib,
  host,
  user,
  system,
  inputs,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert purr != null && purr.user == "alice" && purr.host == "server";
assert purr.arch == "x86_64" && purr.format == "linux";
assert purrLib != null && (purrLib ? "demo");
assert host == "server";
assert user == "alice";
assert builtins.isString system;
assert inputs != null;
{
  home.stateVersion = "24.11";
  home.packages = [ "alice-pkg" ];
  activationPackage = "activation-alice";
}
