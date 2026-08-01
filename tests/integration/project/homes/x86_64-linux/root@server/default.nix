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
assert purr != null && purr.user == "root" && purr.host == "server";
assert purrLib != null && (purrLib ? "demo");
assert host == "server";
assert user == "root";
{
  home.stateVersion = "24.11";
  activationPackage = "activation-root";
}
