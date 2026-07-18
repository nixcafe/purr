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
    ++ (runGroup "buildHomeConfigs" configs.buildHomeConfigs)
    ++ (runGroup "buildSystemConfigs" configs.buildSystemConfigs)
    ++ (runGroup "buildHomeConfigsExtra" configs.buildHomeConfigsExtra)
    ++ (runGroup "parseArchFormat" configs.parseArchFormat)
    ++ (runGroup "parseUserHost" configs.parseUserHost);
in
failures
