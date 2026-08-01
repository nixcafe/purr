{
  config,
  lib,
  namespace,
  purr,
  purrLib,
  host,
  user,
  system,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert purr != null && purr.user == "alice" && purr.host == "macbook";
assert purr.arch == "aarch64" && purr.format == "darwin";
assert purr.isDarwin == true && purr.isLinux == false;
assert purrLib != null && (purrLib ? "demo");
assert host == "macbook";
assert user == "alice";
{
  home.stateVersion = "24.11";
  activationPackage = "activation-macbook";
}
