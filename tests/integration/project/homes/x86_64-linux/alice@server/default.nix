{
  config,
  lib,
  namespace,
  purr,
  host,
  user,
  system,
  inputs,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert purr != null && purr.meta.user == "alice" && purr.meta.host == "server";
assert purr.meta.arch == "x86_64" && purr.meta.format == "linux";
assert purr.systemMeta != null && purr.systemMeta.name == "server";
assert purr.systemMeta.tier == "prod";
assert purr.systemMetas.server.name == "server";
# The merged namespace lib is uniformly available as `purr.lib` in both
# standalone and bridged homes (bridged homes keep home-manager's own `lib`).
assert purr.lib != null && (purr.lib ? "demo");
assert host == "server";
assert user == "alice";
assert builtins.isString system;
assert inputs != null;
{
  home.stateVersion = "24.11";
  home.packages = [ "alice-pkg" ];
  activationPackage = "activation-alice";
}
