let

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  eachSystem =
    systems: f:
    let
      op = attrs: system: attrs // { "${system}" = f system; };
    in
    builtins.foldl' op { } systems;

  eachDefaultSystem = eachSystem defaultSystems;
in
{
  inherit
    defaultSystems
    eachDefaultSystem
    eachSystem
    ;
}
