{ lib }:
let
  inherit (lib) filter head;

  resolveDir =
    src: dir: candidates:
    if dir != null then
      dir
    else
      let
        found = filter (d: builtins.pathExists (src + "/${d}")) candidates;
      in
      if found != [ ] then head found else null;

  resolveDirs = src: cfg: {
    checksDir = resolveDir src cfg.checksDir [ "checks" ];
    shellsDir = resolveDir src cfg.shellsDir [
      "shells"
      "devShells"
    ];
    overlaysDir = resolveDir src cfg.overlaysDir [ "overlays" ];
    packagesDir = resolveDir src cfg.packagesDir [ "packages" ];
    appsDir = resolveDir src cfg.appsDir [ "apps" ];
    templatesDir = resolveDir src cfg.templatesDir [ "templates" ];
    systemsDir = resolveDir src cfg.systemsDir [
      "systems"
      "hosts"
    ];
    homesDir = resolveDir src cfg.homesDir [ "homes" ];
    formatterDir = resolveDir src cfg.formatterDir [
      "formatters"
      "formatter"
    ];
    legacyPackagesDir = resolveDir src cfg.legacyPackagesDir [ "legacyPackages" ];
    libDir = resolveDir src cfg.libDir [ "lib" ];
  };
in
{
  inherit resolveDir resolveDirs;
}
