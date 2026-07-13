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

  fs = import ./lib/fs.nix {
    inherit lib;
  };

  modulesLib = import ./lib/modules.nix {
    inherit fs lib;
  };

  namespacedModules = import ./lib/namespacedModules.nix { };
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
        home = [
          "home"
          "shared"
        ];
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
          home = ["home" "shared"];
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
  };

  config = mkIf cfg.enable (
    let
      modulesPath = cfg.src + "/${cfg.modulesDir}";
      discoveredModules = modulesLib.discoverModules modulesPath cfg.moduleTypes;

      wrap =
        modules:
        if cfg.namespace != null then namespacedModules.wrapModuleSet cfg.namespace modules else modules;

      makeLibExtension =
        if cfg.namespace != null && cfg.libDir != null then
          {
            _module.args.lib = lib // {
              ${cfg.namespace} = import (cfg.src + "/${cfg.libDir}") { inherit lib; };
            };
          }
        else
          null;

      wrapWithLib =
        modules:
        if makeLibExtension != null then
          builtins.mapAttrs (_name: module: {
            imports = [
              makeLibExtension
              module
            ];
          }) modules
        else
          modules;

      wrappedNixos = wrapWithLib (wrap discoveredModules.nixos);
      wrappedDarwin = wrapWithLib (wrap discoveredModules.darwin);
      wrappedHome = wrapWithLib (wrap discoveredModules.home);

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

      discoveredChecks = if checksDir' != null then modulesLib.findModules cfg.src checksDir' else { };

      discoveredShells = if shellsDir' != null then modulesLib.findModules cfg.src shellsDir' else { };

      discoveredOverlays =
        if overlaysDir' != null then modulesLib.findModules cfg.src overlaysDir' else { };
    in
    {
      flake = {
        nixosModules = wrappedNixos;
        darwinModules = wrappedDarwin;
        homeModules = wrappedHome;
        overlays = discoveredOverlays;
      };

      perSystem = flake-parts-lib.mkPerSystemOption (
        { pkgs, ... }:
        {
          _file = ./flake-module.nix;

          config =
            { }
            // lib.optionalAttrs (discoveredChecks != { }) {
              checks = builtins.mapAttrs (_: import) discoveredChecks;
            }
            // lib.optionalAttrs (discoveredShells != { }) {
              devShells = builtins.mapAttrs (_: module: import module { inherit pkgs; }) discoveredShells;
            };
        }
      );
    }
  );
}
