{ lib }:
let
  attrs = import ./lib/attrs.nix;

  systems = import ./lib/systems.nix;

  fs = import ./lib/fs.nix;

  mods = import ./lib/modules.nix {
    inherit fs lib;
  };

  nsm = import ./lib/namespacedModules.nix;

  confs = import ./lib/configs.nix {
    inherit lib;
  };

  resolver = import ./lib/resolveDir.nix {
    inherit lib;
  };

  libBuilder = import ./lib/purrLib.nix {
    inherit lib attrs;
    modules = mods;
    namespacedModules = nsm;
  };

  autoMods = import ./lib/autoModules.nix {
    modules = mods;
  };

  mkFlakeMod = import ./lib/mkFlake.nix {
    inherit
      attrs
      confs
      lib
      mods
      nsm
      systems
      ;
    resolveDir = resolver;
    purrLib = libBuilder;
    autoMods = autoMods;
  };

  hj = import ./lib/hydraJobs.nix {
    inherit lib;
    attrs = attrs;
  };
in
rec {
  # ---- attributes ----
  inherit (attrs) optionalAttrs;

  # ---- systems ----
  inherit (systems) defaultSystems eachDefaultSystem eachSystem;

  # ---- filesystem ----
  inherit (fs) getDefaultNixFiles;

  # ---- modules ----
  inherit (mods)
    collectModules
    discoverHomes
    discoverModules
    discoverSystems
    findModules
    findModulesByName
    findModulesFlat
    findModulesLib
    loadModules
    readDirModules
    mergeModuleTree
    validateByName
    ;

  # ---- namespace wrapping ----
  inherit (nsm) deepMapAttrs wrapModule wrapModuleSet;

  # ---- config builders ----
  inherit (confs)
    buildHomeConfigs
    buildSystemConfigs
    buildSystemRegistry
    findMatchingHomes
    formatOutputKey
    imagesFromConfigs
    parseArchFormat
    parseUserHost
    ;

  # ---- directory resolution ----
  inherit (resolver) resolveDir resolveDirs;

  # ---- library construction ----
  inherit (libBuilder) buildImportedPurrLib buildMergedLib mergePurrLib;

  # ---- auto-discovery ----
  inherit (autoMods)
    autoFormatter
    autoModules
    overlayModules
    templateModules
    ;

  # ---- hydraJobs ----
  inherit (hj)
    buildHydraJobs
    filterSystems
    hydraJobsFromDir
    mirrorOutputs
    ;

  # ---- mkFlake ----
  inherit (mkFlakeMod) mkFlake;
}
