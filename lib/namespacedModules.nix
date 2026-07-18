let
  wrapModule =
    namespace: module:
    {
      pkgs,
      ...
    }@args:
    let
      original = if builtins.isPath module then import module else module;
    in
    # The `false && pkgs != null` is only to reference `pkgs` so deadnix
    # doesn't flag the destructured parameter as unused.
    (if false && pkgs != null then null else original) (args // { inherit namespace; });

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
