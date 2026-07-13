_:
let
  wrapModule =
    namespace: module: args:
    let
      original = if builtins.isPath module then import module else module;
      result = original (args // { inherit namespace; });
    in
    result;

  wrapModuleSet =
    namespace: modules:
    if namespace == null then
      modules
    else
      builtins.mapAttrs (_: module: wrapModule namespace module) modules;
in
{
  inherit
    wrapModule
    wrapModuleSet
    ;
}
