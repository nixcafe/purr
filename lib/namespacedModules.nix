let
  wrapPath =
    namespace: importedPurrLib: path:
    {
      config,
      lib,
      options,
      pkgs,
      inputs,
      system,
      ...
    }@args:
    let
      original = if builtins.isPath path then import path else path;
      libWithNs =
        if namespace != null && importedPurrLib != null then
          lib // { ${namespace} = importedPurrLib; }
        else
          lib;
      result =
        if builtins.isFunction original then
          original (
            args
            // {
              inherit namespace;
              lib = libWithNs;
            }
          )
        else
          original;
      _file = if builtins.isPath path then toString path else null;
    in
    if builtins.isAttrs result && _file != null then result // { inherit _file; } else result;

  wrapModule =
    namespace: importedPurrLib: module:
    if builtins.isAttrs module && (module ? imports || module ? options || module ? config) then
      module
      // {
        imports = builtins.map (
          m: if builtins.isPath m || builtins.isFunction m then wrapPath namespace importedPurrLib m else m
        ) (module.imports or [ ]);
      }
    else if builtins.isPath module || builtins.isFunction module then
      wrapPath namespace importedPurrLib module
    else
      module;

  deepMapAttrs =
    f: value:
    if
      builtins.isAttrs value
      && !builtins.isFunction value
      && !(value ? imports || value ? options || value ? config)
    then
      builtins.mapAttrs (_: deepMapAttrs f) value
    else
      f value;

  wrapModuleSet =
    namespace: importedPurrLib: modules:
    if namespace == null then modules else deepMapAttrs (wrapModule namespace importedPurrLib) modules;
in
{
  inherit
    deepMapAttrs
    wrapModule
    wrapModuleSet
    ;
}
