{ modules }:
let
  importMod =
    pkgs: purrLib: namespace: inputs: extraArgs: module:
    import module (
      pkgs
      // extraArgs
      // {
        inherit inputs pkgs namespace;
        inherit (pkgs) system;
        lib = purrLib;
      }
    );

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
      in
      builtins.mapAttrs (_: path: normalizeOverlay (import path)) overlayMods
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
        import module (
          extraArgs
          // {
            inherit inputs namespace;
            lib = purrLib;
          }
        )
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
