let
  wrapPath =
    namespace: path:
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
      purrLib = args.purrLib or null;
      libWithNs =
        if namespace != null && purrLib != null && purrLib ? ${namespace} then
          lib // { ${namespace} = purrLib.${namespace}; }
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
    namespace: module:
    if builtins.isAttrs module && (module ? imports || module ? options || module ? config) then
      module
      // {
        imports = builtins.map (
          m: if builtins.isPath m || builtins.isFunction m then wrapPath namespace m else m
        ) (module.imports or [ ]);
      }
    else if builtins.isPath module || builtins.isFunction module then
      wrapPath namespace module
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
    namespace: modules:
    if namespace == null then modules else deepMapAttrs (wrapModule namespace) modules;
in
{
  inherit
    deepMapAttrs
    wrapModule
    wrapModuleSet
    ;
}
