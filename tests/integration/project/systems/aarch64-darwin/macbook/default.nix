{
  config,
  lib,
  namespace,
  purr,
  host,
  system,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert
  purr != null
  && purr.meta.name == "macbook"
  && purr.meta.arch == "aarch64"
  && purr.meta.format == "darwin";
assert purr.meta.isDarwin == true && purr.meta.isLinux == false;
assert purr.systemMetas.server.name == "server";
assert host == "macbook";
assert builtins.isString system;
{
  system.stateVersion = "24.11";
  system.build.toplevel = "toplevel-macbook";
  networking.hostName = host;
  services.openssh.enable = true;
}
