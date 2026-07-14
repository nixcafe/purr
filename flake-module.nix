{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.purr;

  fs = import ./lib/fs.nix;

  modulesLib = import ./lib/modules.nix {
    inherit fs lib;
  };

  namespacedModules = import ./lib/namespacedModules.nix;
in
{
  options.purr = {
    enable = mkEnableOption "purr module auto-discovery and namespace support";

    src = mkOption {
      type = types.path;
      description = ''
        Project root directory. Module discovery and other path options
        are computed relative to this directory.
      '';
      example = lib.literalExpression "./.";
    };

    namespace = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Module option namespace. When set, all module options are placed
        under `options.<namespace>.*` and the `namespace` parameter is
        injected into each module's function arguments.
      '';
      example = "cattery";
    };

    libDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path (relative to `src`) to a directory containing library
        functions. When set, the directory is imported and placed under
        `lib.<namespace>`, making functions accessible as
        `lib.<namespace>.someFunc` within module evaluation.
      '';
      example = "lib";
    };

    modulesDir = mkOption {
      type = types.str;
      default = "modules";
      description = ''
        Directory name under `src` containing module subdirectories.
        See {option}`purr.moduleTypes` for which subdirectories are scanned.
      '';
    };

    moduleTypes = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        nixos = [
          "nixos"
          "shared"
        ];
        darwin = [
          "darwin"
          "shared"
        ];
        home = [ "home" ];
      };
      description = ''
        Mapping of flake output module type to subdirectory names
        under {option}`purr.modulesDir`. Modules from all listed
        directories are merged into the corresponding flake output.

        For example, `nixos = ["nixos" "shared" "container"]` will
        scan `modules/nixos/`, `modules/shared/`, and `modules/container/`
        and merge them all into `flake.nixosModules`.
      '';
      example = lib.literalExpression ''
        {
          nixos = ["nixos" "shared" "nixos-musl"];
          darwin = ["darwin" "shared"];
          home = ["home"];
        }
      '';
    };

    checksDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for per-system checks.
        If `null`, auto-detects from `checks/`.
        Each `default.nix` under subdirectories becomes a check.
      '';
    };

    shellsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for devShells.
        If `null`, auto-detects from `shells/` then `devShells/`.
        Each `default.nix` under subdirectories becomes a devShell.
      '';
    };

    overlaysDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for overlays.
        If `null`, auto-detects from `overlays/`.
        Each `default.nix` under subdirectories becomes an overlay.
      '';
    };

    packagesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for per-system packages.
        If `null`, auto-detects from `packages/`.
        Each `default.nix` under subdirectories becomes a package.
      '';
    };

    appsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for per-system apps.
        If `null`, auto-detects from `apps/`.
        Each `default.nix` under subdirectories becomes an app.
      '';
    };

    templatesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for flake templates.
        If `null`, auto-detects from `templates/`.
        Each `default.nix` under subdirectories becomes a template.
      '';
    };

    templatesRecursive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to scan `templates/` recursively.
        When `false` (default), only immediate subdirectories
        with a `default.nix` are discovered. Set to `true` to
        enable nested directory discovery.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      modulesPath = cfg.src + "/${cfg.modulesDir}";
      discoveredModules = modulesLib.discoverModules modulesPath cfg.moduleTypes;

      importedPurrLib =
        if libDir' != null then
          let
            rootModule =
              if builtins.pathExists (cfg.src + "/${libDir'}/default.nix") then
                import (cfg.src + "/${libDir'}/default.nix") { inherit lib; }
              else
                { };
            subModules = modulesLib.findModules cfg.src libDir';
            importedSubModules = namespacedModules.deepMapAttrs (path: import path { inherit lib; }) subModules;
          in
          rootModule // importedSubModules
        else
          null;

      purrLib =
        if importedPurrLib != null then
          if cfg.namespace != null then
            lib // { ${cfg.namespace} = importedPurrLib; }
          else
            lib // importedPurrLib
        else
          lib;

      wrap =
        modules:
        if cfg.namespace != null then namespacedModules.wrapModuleSet cfg.namespace modules else modules;

      makeLibExtension = if importedPurrLib != null then { _module.args.lib = purrLib; } else null;

      wrapWithLib =
        modules:
        if makeLibExtension != null then
          namespacedModules.deepMapAttrs (module: {
            imports = [
              makeLibExtension
              module
            ];
          }) modules
        else
          modules;

      makeModuleSet = name: wrapWithLib (wrap (discoveredModules.${name} or { }));

      resolve =
        dir: candidates:
        if dir != null then
          dir
        else
          let
            found = builtins.filter (d: builtins.pathExists (cfg.src + "/${d}")) candidates;
          in
          if found != [ ] then builtins.head found else null;

      checksDir' = resolve cfg.checksDir [ "checks" ];
      shellsDir' = resolve cfg.shellsDir [
        "shells"
        "devShells"
      ];
      overlaysDir' = resolve cfg.overlaysDir [ "overlays" ];
      packagesDir' = resolve cfg.packagesDir [ "packages" ];
      appsDir' = resolve cfg.appsDir [ "apps" ];
      templatesDir' = resolve cfg.templatesDir [ "templates" ];
      libDir' = resolve cfg.libDir [ "lib" ];

      discoveredOverlays =
        if overlaysDir' != null then
          let
            overlayModules = modulesLib.findModules cfg.src overlaysDir';
          in
          builtins.mapAttrs (_: import) overlayModules
        else
          { };

      discoveredTemplates =
        if templatesDir' != null then
          let
            scan = if cfg.templatesRecursive then modulesLib.findModules else modulesLib.findModulesFlat;
          in
          scan cfg.src templatesDir'
        else
          { };

      autoModules =
        pkgs: dir:
        if dir != null then
          let
            mods = modulesLib.findModules cfg.src dir;
          in
          builtins.mapAttrs (
            _: module:
            import module {
              inherit pkgs;
              inherit (cfg) namespace;
              inherit (pkgs) system;
              lib = purrLib;
            }
          ) mods
        else
          { };
    in
    {
      flake = {
        nixosModules = makeModuleSet "nixos";
        darwinModules = makeModuleSet "darwin";
        homeModules = makeModuleSet "home";
        overlays = discoveredOverlays;
        templates = discoveredTemplates;
      };

      perSystem = flake-parts-lib.mkPerSystemOption (
        { pkgs, ... }:
        let
          mod = autoModules pkgs;

          checksModules = mod checksDir';
          shellsModules = mod shellsDir';
          packagesModules = mod packagesDir';
          appsModules = mod appsDir';
        in
        {
          _file = ./flake-module.nix;

          config =
            { }
            // lib.optionalAttrs (checksModules != { }) {
              checks = checksModules;
            }
            // lib.optionalAttrs (shellsModules != { }) {
              devShells = shellsModules;
            }
            // lib.optionalAttrs (packagesModules != { }) {
              packages = packagesModules;
            }
            // lib.optionalAttrs (appsModules != { }) {
              apps = appsModules;
            };
        }
      );
    }
  );
}
