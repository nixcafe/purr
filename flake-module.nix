{
  config,
  lib,
  flake-parts-lib,
  inputs,
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

  nsm = import ./lib/namespacedModules.nix;

  fs = import ./lib/fs.nix;

  mods = import ./lib/modules.nix {
    inherit fs lib;
  };

  confs = import ./lib/configs.nix {
    inherit lib;
  };

  attrs = import ./lib/attrs.nix;

  resolver = import ./lib/resolveDir.nix {
    inherit lib;
  };

  libBuilder = import ./lib/purrLib.nix {
    inherit lib attrs;
    modules = mods;
    namespacedModules = nsm;
  };

  autoMods = import ./lib/autoModules.nix {
    modules = mods;
  };

  inherit (resolver) resolveDirs;
  inherit (libBuilder) buildImportedPurrLib mergePurrLib;
  inherit (autoMods) autoModules overlayModules templateModules;
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

    flattenLib = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to flatten the lib directory hierarchy. When `false`
        (default), `lib/foo/default.nix` is accessible as
        `lib.<namespace>.foo.someFunc`. When `true`, all subdirectory
        modules are merged directly into `lib.<namespace>`, so
        `lib/foo/default.nix` functions become
        `lib.<namespace>.someFunc`.
      '';
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

    extraModules = mkOption {
      type = types.attrsOf (types.listOf types.raw);
      default = { };
      description = ''
        External modules to merge into flake outputs.
        Keys are module types (`nixos`, `darwin`, `home`),
        values are lists of modules.
      '';
      example = lib.literalExpression ''
        {
          nixos = [
            inputs.some-flake.nixosModules.default
            inputs.disko.nixosModules.default
          ];
        }
      '';
    };

    bundleModules = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to bundle all modules into a `default` module.
        When enabled, a `default` key is added to each module output
        (nixosModules, darwinModules, homeModules) that imports all
        sub-modules. Skipped if the module set already contains a
        `default` key.
      '';
    };

    bundleExtraModules = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to include {option}`purr.extraModules` in the
        auto-generated `default` bundle. Ignored when
        {option}`purr.bundleModules` is `false`.
      '';
    };

    systemsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for system/host configurations.
        If `null`, auto-detects from `systems/` then `hosts/`.
        Each subdirectory named `<arch>-<format>/<name>/default.nix`
        becomes a flake configuration.
      '';
    };

    homesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for home-manager configurations.
        If `null`, auto-detects from `homes/`.
        Each subdirectory named `<arch>-<format>/<user>@<host>/default.nix`
        becomes a home configuration. Homes with a matching host name
        are automatically linked when home-manager is available.
      '';
    };

    nixpkgsConfig = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        nixpkgs config attributes such as `allowUnfree` and
        `permittedInsecurePackages`. This is passed to:
        - nixpkgs imports for per-system packages, shells, and checks
        - `buildHomeConfigs` for home-manager nixpkgs import
        - `buildSystemConfigs` (injected as
          `nixpkgs.config = lib.mkDefault nixpkgsConfig`
          into each system module)
        Settings can be overridden per-system via
        `nixpkgs.config` in the host/home module.
      '';
    };

    autoInject = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to auto-inject configuration from purr metadata.
        When enabled:
        - system configs get `networking.hostName = <name>`
        - home configs get `home.username` and `home.homeDirectory`
        All injected with `lib.mkDefault`, so explicit settings
        in your modules will override.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      resolved = resolveDirs cfg.src {
        inherit (cfg)
          checksDir
          shellsDir
          overlaysDir
          packagesDir
          appsDir
          templatesDir
          systemsDir
          homesDir
          libDir
          ;
      };

      modulesPath = cfg.src + "/${cfg.modulesDir}";
      discoveredModules = mods.discoverModules modulesPath cfg.moduleTypes;

      importedPurrLib = buildImportedPurrLib {
        inherit inputs;
        inherit (cfg) src namespace flattenLib;
        inherit (resolved) libDir;
      };

      mergedLib = mergePurrLib lib importedPurrLib cfg.namespace;

      wrap =
        modules:
        if cfg.namespace != null then nsm.wrapModuleSet cfg.namespace importedPurrLib modules else modules;

      makeLibExtension = if importedPurrLib != null then { _module.args.lib = mergedLib; } else null;

      wrapWithLib =
        modules:
        if makeLibExtension != null then
          nsm.deepMapAttrs (module: {
            imports = [
              makeLibExtension
              module
            ];
          }) modules
        else
          modules;

      listExtraModules =
        list:
        builtins.listToAttrs (
          lib.imap0 (i: m: {
            name = "extra-${toString i}";
            value = m;
          }) list
        );

      extra = builtins.mapAttrs (_: listExtraModules) cfg.extraModules;

      makeModuleSet = name: wrapWithLib (wrap (discoveredModules.${name} or { }));

      makeBundled =
        name:
        let
          authored = makeModuleSet name;
          everything = lib.recursiveUpdate authored (extra.${name} or { });
        in
        if cfg.bundleModules then
          let
            toBundle = if cfg.bundleExtraModules then everything else authored;
          in
          authored
          // lib.optionalAttrs (!(everything ? "default")) {
            default = {
              imports = mods.collectModules toBundle;
            };
          }
        else
          authored;

      discoveredOverlays = overlayModules cfg.src resolved.overlaysDir;

      discoveredTemplates =
        templateModules cfg.src resolved.templatesDir cfg.templatesRecursive mergedLib cfg.namespace
          inputs;

      discoveredSystems =
        if resolved.systemsDir != null then mods.discoverSystems cfg.src resolved.systemsDir else { };

      discoveredHomes =
        if resolved.homesDir != null then mods.discoverHomes cfg.src resolved.homesDir else { };

      buildSystemConfigs =
        if discoveredSystems != { } then
          confs.buildSystemConfigs {
            inherit
              discoveredHomes
              discoveredSystems
              inputs
              ;
            inherit (cfg)
              autoInject
              namespace
              nixpkgsConfig
              extraModules
              ;
            lib = mergedLib;
            sharedOverlays = builtins.attrValues discoveredOverlays;
          }
        else
          { };

      buildHomeConfigs =
        if discoveredHomes != { } then
          confs.buildHomeConfigs {
            inherit discoveredHomes inputs;
            inherit (cfg)
              autoInject
              namespace
              nixpkgsConfig
              extraModules
              ;
            sharedOverlays = builtins.attrValues discoveredOverlays;
          }
        else
          { };
    in
    {
      flake = buildSystemConfigs // {
        nixosModules = makeBundled "nixos";
        darwinModules = makeBundled "darwin";
        homeModules = makeBundled "home";
        overlays = discoveredOverlays;
        templates = discoveredTemplates;
        homeConfigurations = buildHomeConfigs;
      };

      perSystem = flake-parts-lib.mkPerSystemOption (
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config = cfg.nixpkgsConfig;
            overlays = builtins.attrValues discoveredOverlays;
          };
          mod = autoModules cfg.src pkgs mergedLib cfg.namespace inputs;

          checksModules = mod resolved.checksDir;
          shellsModules = mod resolved.shellsDir;
          packagesModules = mod resolved.packagesDir;
          appsModules = mod resolved.appsDir;
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
