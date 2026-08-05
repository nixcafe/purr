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
assert purr != null && purr.meta.user == "alice" && purr.meta.host == "macbook";
assert purr.meta.arch == "aarch64" && purr.meta.format == "darwin";
assert purr.meta.isDarwin == true && purr.meta.isLinux == false;
assert purr.systemMeta != null && purr.systemMeta.name == "macbook";
assert purr.systemMetas.server.name == "server";
assert purr.lib != null && (purr.lib ? "demo");
assert host == "macbook";
assert user == "alice";
{
  home.stateVersion = "24.11";
  activationPackage = "activation-macbook";
}
