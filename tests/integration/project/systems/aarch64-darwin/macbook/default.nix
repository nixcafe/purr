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
assert purr != null && purr.name == "macbook" && purr.arch == "aarch64" && purr.format == "darwin";
assert purr.isDarwin == true && purr.isLinux == false;
assert host == "macbook";
assert builtins.isString system;
{
  system.stateVersion = "24.11";
  system.build.toplevel = "toplevel-macbook";
  networking.hostName = host;
  services.openssh.enable = true;
}
