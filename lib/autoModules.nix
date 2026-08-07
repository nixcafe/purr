{ modules }:
let
  inherit (import ./args.nix) purrArgs;

  importMod =
    pkgs: purrLib: namespace: inputs: extraArgs: module:
    let
      raw = import module;
    in
    if builtins.isFunction raw then
      raw (
        pkgs
        // (purrArgs {
          inherit
            extraArgs
            inputs
            namespace
            ;
          lib = purrLib;
        })
        // {
          inherit pkgs;
          inherit (pkgs) system;
        }
      )
    else
      raw;

  autoModules =
    src: pkgs: purrLib: namespace: inputs: extraArgs: dir: packagesByName:
    if dir != null then
      let
        regularMods = modules.findModulesLib src dir;
        byNameMods = if packagesByName then modules.findModulesByName src dir else { };
        allMods = regularMods // byNameMods;
      in
      builtins.mapAttrs (_: importMod pkgs purrLib namespace inputs extraArgs) allMods
    else
      { };

  autoFormatter =
    src: pkgs: purrLib: namespace: inputs: extraArgs: dir:
    if dir != null then
      let
        f = src + "/${dir}/default.nix";
      in
      if builtins.pathExists f then importMod pkgs purrLib namespace inputs extraArgs f else null
    else
      null;

  overlayModules =
    src: overlaysDir:
    if overlaysDir != null then
      let
        overlayMods = modules.findModulesLib src overlaysDir;
        normalizeOverlay =
          fn: final: prev:
          let
            result = fn final prev;
          in
          if builtins.isFunction result then result prev else result;
        # Pass plain `final: prev: attrs` overlays through unwrapped so they
        # keep their own source position: nix-repl shows the user's overlay
        # file (overlays/<name>/default.nix) instead of purr's wrapper lambda.
        # Only wrap when normalization is actually needed — probing with dummy
        # args yields a function (curried/function-returning overlays) or throws.
        passThrough =
          fn:
          if !builtins.isFunction fn then
            fn
          else
            let
              probe = builtins.tryEval (builtins.isFunction (fn null null));
            in
            if probe.success && !probe.value then fn else normalizeOverlay fn;
      in
      builtins.mapAttrs (_: path: passThrough (import path)) overlayMods
    else
      { };

  templateModules =
    src: templatesDir: templatesRecursive: purrLib: namespace: inputs: extraArgs:
    if templatesDir != null then
      let
        scan = if templatesRecursive then modules.findModulesLib else modules.findModulesFlat;
        mods = scan src templatesDir;
      in
      builtins.mapAttrs (
        _: module:
        let
          raw = import module;
        in
        if builtins.isFunction raw then
          raw (purrArgs {
            inherit
              extraArgs
              inputs
              namespace
              ;
            lib = purrLib;
          })
        else
          raw
      ) mods
    else
      { };
in
{
  inherit
    autoFormatter
    autoModules
    overlayModules
    templateModules
    ;
}
