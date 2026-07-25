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

          rootModule =
            if builtins.pathExists (src + "/${libDir}/default.nix") then
              import (src + "/${libDir}/default.nix") {
                inherit inputs namespace;
                lib = mergedLib // optionalAttrs (namespace != null) { ${namespace} = self; };
              }
            else
              { };

          subModules = modules.findModulesLib src libDir;
          importedSubModules = namespacedModules.deepMapAttrs (
            path:
            import path {
              inherit inputs namespace;
              lib = mergedLib // optionalAttrs (namespace != null) { ${namespace} = self; };
            }
          ) subModules;

          nested = rootModule // importedSubModules;

          flatMerge =
            let
              collectLeaf =
                v:
                if builtins.isAttrs v then
                  let
                    direct = v."default.nix" or null;
                    rest = builtins.removeAttrs v [ "default.nix" ];
                    sub = concatMap collectLeaf (builtins.attrValues rest);
                  in
                  (if direct != null then [ direct ] else [ ]) ++ sub
                else
                  [ ];
            in
            foldl' (a: b: a // b) rootModule (collectLeaf importedSubModules);
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
