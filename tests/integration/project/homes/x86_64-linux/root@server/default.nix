{
  config,
  lib,
  namespace,
  purr,
  host,
  user,
  system,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert purr != null && purr.meta.user == "root" && purr.meta.host == "server";
assert purr.systemMeta != null && purr.systemMeta.name == "server";
assert purr.lib != null && (purr.lib ? "demo");
assert host == "server";
assert user == "root";
{
  home.stateVersion = "24.11";
  activationPackage = "activation-root";
}
