let
  wrapPath =
    namespace: path: args:
    let
      original = if builtins.isPath path then import path else path;
    in
    original (args // { inherit namespace; });

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
