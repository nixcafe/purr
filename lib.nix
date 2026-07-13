{ lib }:
let
  eachSystem = import ./lib/eachSystem.nix { };

  attrs = import ./lib/attrs.nix {
    inherit lib;
  };

  fs = import ./lib/fs.nix {
    inherit lib;
  };

  modules = import ./lib/modules.nix {
    inherit fs lib;
  };

  namespacedModules = import ./lib/namespacedModules.nix { };

  mkFlake = import ./lib/mkFlake.nix {
    inherit
      attrs
      eachSystem
      lib
      modules
      namespacedModules
      ;
  };
in
{
  inherit (eachSystem) eachSystem eachDefaultSystem defaultSystems;
  inherit (mkFlake) mkFlake;
  inherit (modules) collectModules loadModules;
}
