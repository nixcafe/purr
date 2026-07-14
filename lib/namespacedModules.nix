let
  wrapModule =
    namespace: module: args:
    let
      original = if builtins.isPath module then import module else module;
      result = original (args // { inherit namespace; });
    in
    result;

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
