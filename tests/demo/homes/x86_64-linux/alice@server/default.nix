{
  config,
  pkgs,
  lib,
  namespace,
  purr,
  purrLib,
  inputs,
  host,
  system,
  ...
}:
assert purr != null;
assert purrLib != null;
assert builtins.isString host;
assert lib != null;
let
  resolvedUser =
    if (purr ? user) && purr.user != null then
      purr.user
    else
      let
        matches = builtins.filter (h: h.host == host) (purr.homes or [ ]);
      in
      if matches != [ ] then (builtins.head matches).user else "unknown";
in
{
  home.stateVersion = "24.11";
  home.packages = [ pkgs.hello ];

  home.file."purr-test-home".text = ''
    namespace=${namespace}
    user=${resolvedUser}
    host=${host}
    arch=${purr.arch}
    format=${purr.format}
    libHasNamespace=${toString (purrLib ? "demo")}
    greeting=${purrLib.demo.greet "home"}
  '';
}
