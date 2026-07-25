{ modules }:
let
  autoModules =
    src: pkgs: purrLib: namespace: inputs: dir:
    if dir != null then
      let
        mods = modules.findModulesLib src dir;
      in
      builtins.mapAttrs (
        _: module:
        import module {
          inherit inputs pkgs namespace;
          inherit (pkgs) system;
          lib = purrLib;
        }
      ) mods
    else
      { };

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
    src: templatesDir: templatesRecursive: purrLib: namespace: inputs:
    if templatesDir != null then
      let
        scan = if templatesRecursive then modules.findModulesLib else modules.findModulesFlat;
        mods = scan src templatesDir;
      in
      builtins.mapAttrs (
        _: module:
        import module {
          inherit inputs namespace;
          lib = purrLib;
        }
      ) mods
    else
      { };
in
{
  inherit autoModules overlayModules templateModules;
}
