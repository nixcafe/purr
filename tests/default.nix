# Test runner for purr.
# Each test file corresponds to a module under lib/.
{ lib }:
let
  runTests = lib.debug.runTests;

  testAttrs = import ./test-attrs.nix { inherit lib; };

  testSystems = import ./test-systems.nix { inherit lib; };

  testFs = import ./test-fs.nix { inherit lib; };

  testModules = import ./test-modules.nix { inherit lib; };

  testNamespacedModules = import ./test-namespacedModules.nix { inherit lib; };

  testConfigs = import ./test-configs.nix { inherit lib; };

  testResolveDir = import ./test-resolveDir.nix { inherit lib; };

  testPurrLib = import ./test-purrLib.nix { inherit lib; };

  testAutoModules = import ./test-autoModules.nix { inherit lib; };

  testMkFlake = import ./test-mkFlake.nix { inherit lib; };

  runGroup = name: tests: runTests { "${name}" = tests; };

  failures =
    (runGroup "optionalAttrs" testAttrs.optionalAttrs)
    ++ (runGroup "eachSystem" testSystems.eachSystem)
    ++ (runGroup "defaultSystems" testSystems.defaultSystems)
    ++ (runGroup "eachDefaultSystem" testSystems.eachDefaultSystem)
    ++ (runGroup "getDefaultNixFiles" testFs.getDefaultNixFiles)
    ++ (runGroup "findModulesFlat" testModules.findModulesFlat)
    ++ (runGroup "findModules" testModules.findModules)
    ++ (runGroup "findModulesLib" testModules.findModulesLib)
    ++ (runGroup "loadModules" testModules.loadModules)
    ++ (runGroup "discoverModules" testModules.discoverModules)
    ++ (runGroup "discoverSystems" testModules.discoverSystems)
    ++ (runGroup "discoverHomes" testModules.discoverHomes)
    ++ (runGroup "collectModules" testModules.collectModules)
    ++ (runGroup "findModulesByName" testModules.findModulesByName)
    ++ (runGroup "validateByName" testModules.validateByName)
    ++ (runGroup "deepMapAttrs" testNamespacedModules.deepMapAttrs)
    ++ (runGroup "wrapModule" testNamespacedModules.wrapModule)
    ++ (runGroup "wrapWithLib" testNamespacedModules.wrapWithLib)
    ++ (runGroup "wrapModuleSet" testNamespacedModules.wrapModuleSet)
    ++ (runGroup "nullNamespace" testNamespacedModules.nullNamespace)
    ++ (runGroup "parseArchFormat" testConfigs.parseArchFormat)
    ++ (runGroup "parseUserHost" testConfigs.parseUserHost)
    ++ (runGroup "formatOutputKey" testConfigs.formatOutputKey)
    ++ (runGroup "findMatchingHomes" testConfigs.findMatchingHomes)
    ++ (runGroup "buildHomeConfigs" testConfigs.buildHomeConfigs)
    ++ (runGroup "buildHomeConfigsExtra" testConfigs.buildHomeConfigsExtra)
    ++ (runGroup "buildSystemConfigs" testConfigs.buildSystemConfigs)
    ++ (runGroup "extraArgs" testConfigs.extraArgs)
    ++ (runGroup "resolveDir" testResolveDir.resolveDir)
    ++ (runGroup "resolveDirs" testResolveDir.resolveDirs)
    ++ (runGroup "mergePurrLib" testPurrLib.mergePurrLib)
    ++ (runGroup "buildImportedPurrLib" testPurrLib.buildImportedPurrLib)
    ++ (runGroup "overlayModules" testAutoModules.overlayModules)
    ++ (runGroup "templateModules" testAutoModules.templateModules)
    ++ (runGroup "autoModules" testAutoModules.autoModules)
    ++ (runGroup "systemsOnly" testMkFlake.systemsOnly)
    ++ (runGroup "homesOnly" testMkFlake.homesOnly)
    ++ (runGroup "systemsAndHomes" testMkFlake.systemsAndHomes)
    ++ (runGroup "fullPipeline" testMkFlake.fullPipeline)
    ++ (runGroup "flattenLib" testMkFlake.flattenLib)
    ++ (runGroup "bundleExtraModules" testMkFlake.bundleExtraModules)
    ++ (runGroup "customModuleTypes" testMkFlake.customModuleTypes)
    ++ (runGroup "customSystems" testMkFlake.customSystems)
    ++ (runGroup "outputsBuilder" testMkFlake.outputsBuilder)
    ++ (runGroup "packagesByName" testMkFlake.packagesByName)
    ++ (runGroup "extraArgs" testMkFlake.extraArgs);
in
failures
