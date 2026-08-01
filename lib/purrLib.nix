{
  lib,
  modules,
  namespacedModules,
  attrs,
}:
let
  inherit (lib) concatMap foldl' fix;
  inherit (attrs) optionalAttrs;

  buildImportedPurrLib =
    {
      src,
      libDir,
      namespace,
      inputs,
      flattenLib,
    }:
    if libDir != null then
      fix (
        self:
        let
          mergedLib = lib;

          # Import a lib module and only call it with arguments when it is a
          # function. Plain attrset modules (e.g. static data) are returned
          # as-is — snowfall behaves the same way.
          call =
            path:
            let
              module = import path;
            in
            if builtins.isFunction module then
              module {
                inherit inputs namespace;
                lib = mergedLib // optionalAttrs (namespace != null) { ${namespace} = self; };
              }
            else
              module;

          rootModule =
            if builtins.pathExists (src + "/${libDir}/default.nix") then
              call (src + "/${libDir}/default.nix")
            else
              { };

          subModules = modules.findModulesLib src libDir;
          importedSubModules = namespacedModules.deepMapAttrs call subModules;

          nested = rootModule // importedSubModules;

          flatMerge =
            let
              collectLeafPaths =
                v: if builtins.isAttrs v then concatMap collectLeafPaths (builtins.attrValues v) else [ v ];
              importedLeaves = builtins.map call (collectLeafPaths subModules);
            in
            foldl' (a: b: a // b) rootModule importedLeaves;
        in
        if flattenLib then flatMerge else nested
      )
    else
      null;

  mergePurrLib =
    lib: importedPurrLib: namespace:
    if importedPurrLib != null then
      if namespace != null then lib // { ${namespace} = importedPurrLib; } else lib // importedPurrLib
    else
      lib;
in
{
  inherit buildImportedPurrLib mergePurrLib;
}
