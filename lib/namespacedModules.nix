let
  wrapModule =
    namespace: module:
    { config, ... }@args:
    let
      original = if builtins.isPath module then import module else module;
      enhancedLib = config._module.args.lib or args.lib;
    in
    original (
      args
      // {
        inherit namespace;
        lib = enhancedLib;
      }
    );

  deepMapAttrs =
    f: value:
    if builtins.isAttrs value && !builtins.isFunction value then
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
