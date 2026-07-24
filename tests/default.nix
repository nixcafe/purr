# Test runner for purr.
# Import this and check returned list is empty for all-pass.
{
  lib,
}:
let
  runTests = lib.debug.runTests;

  attrsSystems = import ./attrs-systems.nix { inherit lib; };

  moduleArgs = import ./module-args.nix { inherit lib; };

  namespacedModules = import ./namespacedModules.nix { inherit lib; };

  collectModules = import ./collectModules.nix { inherit lib; };

  configs = import ./configs.nix { inherit lib; };

  modulesLib = import ./modules-lib.nix { inherit lib; };

  mkFlakeSystems = import ./mkFlake-systems.nix { inherit lib; };

  runGroup = name: tests: runTests { "${name}" = tests; };

  failures =
    (runGroup "optionalAttrs" attrsSystems.optionalAttrs)
    ++ (runGroup "eachSystem" attrsSystems.eachSystem)
    ++ (runGroup "defaultSystems" attrsSystems.defaultSystems)
    ++ (runGroup "eachDefaultSystem" attrsSystems.eachDefaultSystem)
    ++ (runGroup "moduleArgs.wrapModule" moduleArgs.wrapModule)
    ++ (runGroup "moduleArgs.wrapModuleEdgeCases" moduleArgs.wrapModuleEdgeCases)
    ++ (runGroup "moduleArgs.wrapWithLib" moduleArgs.wrapWithLib)
    ++ (runGroup "moduleArgs.wrapModuleSet" moduleArgs.wrapModuleSet)
    ++ (runGroup "moduleArgs.nullNamespace" moduleArgs.nullNamespace)
    ++ (runGroup "deepMapAttrs" namespacedModules.deepMapAttrs)
    ++ (runGroup "wrapModuleSet" namespacedModules.wrapModuleSet)
    ++ (runGroup "collectModules" collectModules.basic)
    ++ (runGroup "getDefaultNixFiles" modulesLib.getDefaultNixFiles)
    ++ (runGroup "findModulesFlat" modulesLib.findModulesFlat)
    ++ (runGroup "findModules" modulesLib.findModules)
    ++ (runGroup "findModulesLib" modulesLib.findModulesLib)
    ++ (runGroup "loadModules" modulesLib.loadModules)
    ++ (runGroup "discoverModules" modulesLib.discoverModules)
    ++ (runGroup "discoverSystems" modulesLib.discoverSystems)
    ++ (runGroup "discoverHomes" modulesLib.discoverHomes)
    ++ (runGroup "buildHomeConfigs" configs.buildHomeConfigs)
    ++ (runGroup "buildSystemConfigs" configs.buildSystemConfigs)
    ++ (runGroup "buildHomeConfigsExtra" configs.buildHomeConfigsExtra)
    ++ (runGroup "parseArchFormat" configs.parseArchFormat)
    ++ (runGroup "parseUserHost" configs.parseUserHost)
    ++ (runGroup "mkFlake.systemsOnly" mkFlakeSystems.systemsOnly)
    ++ (runGroup "mkFlake.homesOnly" mkFlakeSystems.homesOnly)
    ++ (runGroup "mkFlake.systemsAndHomes" mkFlakeSystems.systemsAndHomes)
    ++ (runGroup "mkFlake.fullPipeline" mkFlakeSystems.fullPipeline);
in
failures
