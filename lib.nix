{ lib }:
let
  systems = import ./lib/systems.nix;

  attrs = import ./lib/attrs.nix;

  fs = import ./lib/fs.nix;

  modules = import ./lib/modules.nix {
    inherit fs lib;
  };

  configs = import ./lib/configs.nix {
    inherit lib;
  };

  namespacedModules = import ./lib/namespacedModules.nix;

  mkFlake = import ./lib/mkFlake.nix {
    inherit
      attrs
      configs
      lib
      modules
      namespacedModules
      systems
      ;
  };
in
{
  inherit (systems) eachSystem eachDefaultSystem defaultSystems;
  inherit (mkFlake) mkFlake;
  inherit (modules) collectModules loadModules;
}
