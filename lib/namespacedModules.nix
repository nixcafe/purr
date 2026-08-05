# Namespace wrapping: bind purr's own keys (namespace, namespace lib, and the
# defining flake's inputs) into each module at definition time, while still
# forwarding the module system's runtime args (pkgs, system, config,
# _module.args users, etc.).
#
# The defining flake's `inputs` are captured here (not taken from the consumer's
# args) so that a module can reference inputs its own flake declares — e.g. a
# library flake's module using `inputs.develop-templates`. This mirrors
# snowfall-lib's `create-modules`, which injects `inputs = user-inputs` when
# instantiating each project module.
let
  wrapPath =
    namespace: importedPurrLib: inputs: path:
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }@args:
    let
      original = if builtins.isPath path then import path else path;
      libWithNs =
        if namespace != null && importedPurrLib != null then
          lib // { ${namespace} = importedPurrLib; }
        else
          lib;
      # Resolve each argument the original module declares, falling back to
      # `config._module.args` exactly like the module system itself does in
      # `applyModuleArgs`. A plain `args // { ... }` would drop args that are
      # only provided via `_module.args` (e.g. `user`), because those are not
      # physically present in `args` unless declared by the wrapper function.
      # `inputs` is forced to the defining flake's inputs rather than the
      # consumer's, so modules see the inputs their own flake declared.
      forwardedArgs =
        (builtins.mapAttrs (name: _: args.${name} or config._module.args.${name}) (
          builtins.functionArgs original
        ))
        // {
          inherit
            inputs
            namespace
            ;
          lib = libWithNs;
        };
      result = if builtins.isFunction original then original forwardedArgs else original;
      _file = if builtins.isPath path then toString path else null;
    in
    if builtins.isAttrs result && _file != null then result // { inherit _file; } else result;

  wrapModule =
    namespace: importedPurrLib: inputs: module:
    if builtins.isAttrs module && (module ? imports || module ? options || module ? config) then
      module
      // {
        imports = builtins.map (
          m:
          if builtins.isPath m || builtins.isFunction m then
            wrapPath namespace importedPurrLib inputs m
          else
            m
        ) (module.imports or [ ]);
      }
    else if builtins.isPath module || builtins.isFunction module then
      wrapPath namespace importedPurrLib inputs module
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
    namespace: importedPurrLib: inputs: modules:
    if namespace == null then
      modules
    else
      deepMapAttrs (wrapModule namespace importedPurrLib inputs) modules;
in
{
  inherit
    deepMapAttrs
    wrapModule
    wrapModuleSet
    ;
}
