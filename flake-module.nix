{
  config,
  lib,
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

  hj = import ./lib/hydraJobs.nix {
    inherit lib attrs;
  };

  systemsMod = import ./lib/systems.nix;

  inherit (resolver) resolveDirs;
  inherit (libBuilder) buildImportedPurrLib mergePurrLib;
  inherit (autoMods)
    autoFormatter
    autoModules
    overlayModules
    templateModules
    ;
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

    packagesByName = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to also discover packages using the by-name convention.
        When enabled, packages are discovered from
        `<packagesDir>/by-name/<shard>/<name>/package.nix` in addition
        to the standard `<packagesDir>/<name>/default.nix` pattern.
        Coexists with regular package discovery.
      '';
    };

    legacyPackagesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for per-system legacy packages.
        If `null`, auto-detects from `legacyPackages/`.
        Each `default.nix` under subdirectories becomes a legacy package.
      '';
    };

    legacyPackagesByName = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to also discover legacy packages using the by-name convention.
        Same semantics as {option}`purr.packagesByName`.
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

    formatterDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory name under `src` for the per-system formatter.
        If `null`, auto-detects from `formatters/` then `formatter/`.
        The `default.nix` in this directory is imported per-system
        and must return a derivation (e.g. `pkgs.nixfmt-rfc-style`).
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

    extraArgs = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Additional arguments to pass to every module. These are merged
        into the argument set for all auto-discovered modules —
        packages, shells, checks, apps, templates — as well as
        system `specialArgs` and home `extraSpecialArgs`.
        Purr's own keys (inputs, pkgs, namespace, lib, system, purr)
        always override `extraArgs` in case of naming conflicts.
      '';
      example = lib.literalExpression ''
        {
          customConfigPath = "/etc/myapp";
          deploymentTarget = "production";
        }
      '';
    };

    outputsBuilder = mkOption {
      type = types.raw;
      default = _: { };
      description = ''
        Additional per-system outputs. Called for each system with
        `{ pkgs, system, lib, inputs, namespace }` and must return
        an attrset that is merged into the perSystem flake outputs.
        Use this for custom outputs like `formatter` or any other
        per-system key not covered by purr's auto-discovery.
      '';
      example = lib.literalExpression ''
        {
          pkgs,
          lib,
          namespace,
          ...
        }: {
          formatter = pkgs.nixfmt-rfc-style;
        }
      '';
    };

    hydraJobs = {
      enable = mkEnableOption "hydraJobs flake output with automatic derivation discovery";

      dir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Directory name under `src` for Hydra CI job definitions.
          If `null`, auto-detects from `hydraJobs/`.
          Each subdirectory `<group>/<job>/default.nix` is a function
          `{ pkgs, system, lib, inputs, namespace }` that returns a
          derivation, derivation attrset, or `null`.
          Produces `hydraJobs.<group>.<system>.<job>`.
        '';
      };

      systems = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          System architectures to include in `hydraJobs` output.
          When `null` (default), all flake systems are included.
          Set to e.g. `["x86_64-linux"]` to restrict CI jobs.
        '';
      };

      include = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          Mirror existing outputs into hydraJobs.
          When `null` (default), auto-detects all available outputs.
          Set to `[]` to disable mirroring, or explicitly list names.
          Valid per-system names: checks, packages, devShells, apps,
          legacyPackages, formatter.
          Valid config names: nixosConfigs, darwinConfigs, homeConfigs.
          Note: apps are not included by auto-detection even if present
          because they are not derivations.
        '';
      };

      extra = mkOption {
        type = types.attrs;
        default = { };
        description = ''
          Additional hydraJobs attributes merged at top level.
          Has highest priority and can override any job from
          directory discovery or output mirroring.
        '';
      };
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
          formatterDir
          legacyPackagesDir
          templatesDir
          systemsDir
          homesDir
          libDir
          ;
        hydraJobsDir = cfg.hydraJobs.dir;
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
        authored
        // lib.optionalAttrs (!(everything ? "default")) {
          default = {
            imports = mods.collectModules (
              if cfg.bundleModules then if cfg.bundleExtraModules then everything else authored else authored
            );
          };
        };

      discoveredOverlays = overlayModules cfg.src resolved.overlaysDir;

      discoveredTemplates =
        templateModules cfg.src resolved.templatesDir cfg.templatesRecursive mergedLib cfg.namespace inputs
          cfg.extraArgs;

      discoveredSystems =
        if resolved.systemsDir != null then mods.discoverSystems cfg.src resolved.systemsDir else { };

      discoveredHomes =
        if resolved.homesDir != null then mods.discoverHomes cfg.src resolved.homesDir else { };

      nixosModules = makeBundled "nixos";
      darwinModules = makeBundled "darwin";
      homeModules = makeBundled "home";

      extraModulesWithLocal = {
        nixos =
          cfg.extraModules.nixos or [ ] ++ lib.optional (nixosModules ? "default") nixosModules.default;
        darwin =
          cfg.extraModules.darwin or [ ] ++ lib.optional (darwinModules ? "default") darwinModules.default;
        home = cfg.extraModules.home or [ ] ++ lib.optional (homeModules ? "default") homeModules.default;
      };

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
              extraArgs
              namespace
              nixpkgsConfig
              ;
            extraModules = extraModulesWithLocal;
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
              extraArgs
              namespace
              nixpkgsConfig
              ;
            extraModules = extraModulesWithLocal;
            lib = mergedLib;
            sharedOverlays = builtins.attrValues discoveredOverlays;
          }
        else
          { };

      images = hj.imagesFromConfigs (buildSystemConfigs.imageRecipes or { }) (
        cfg.hydraJobs.systems or null
      );

      hydraJobs =
        if cfg.hydraJobs.enable then
          let
            systemPkgs = builtins.listToAttrs (
              builtins.map (system: {
                name = system;
                value = import inputs.nixpkgs {
                  inherit system;
                  config = cfg.nixpkgsConfig;
                  overlays = builtins.attrValues discoveredOverlays;
                };
              }) systemsMod.defaultSystems
            );
          in
          hj.buildHydraJobs {
            inherit (cfg)
              extraArgs
              namespace
              src
              ;
            inherit inputs;
            inherit (resolved) hydraJobsDir;
            hydraSystems = cfg.hydraJobs.systems;
            hydraJobsInclude = cfg.hydraJobs.include;
            hydraJobsExtra = cfg.hydraJobs.extra;
            inherit systemPkgs;
            lib = mergedLib;
            perSystemOutputs = { };
            systemConfigs = buildSystemConfigs;
            homeConfigs = buildHomeConfigs;
          }
        else
          { };
    in
    {
      flake =
        lib.removeAttrs buildSystemConfigs [ "imageRecipes" ]
        // {
          inherit
            darwinModules
            homeModules
            nixosModules
            ;
          overlays = discoveredOverlays;
          templates = discoveredTemplates;
          homeConfigurations = buildHomeConfigs;
        }
        // lib.optionalAttrs (images != { }) { inherit images; }
        // lib.optionalAttrs cfg.hydraJobs.enable { inherit hydraJobs; }
        // lib.optionalAttrs (importedPurrLib != null) (
          if cfg.namespace != null then
            {
              lib = {
                ${cfg.namespace} = importedPurrLib;
              };
            }
          else
            { lib = importedPurrLib; }
        );

      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config = cfg.nixpkgsConfig;
            overlays = builtins.attrValues discoveredOverlays;
          };
          mod = autoModules cfg.src pkgs mergedLib cfg.namespace inputs cfg.extraArgs;

          checksModules = mod resolved.checksDir false;
          shellsModules = mod resolved.shellsDir false;
          packagesModules = mod resolved.packagesDir cfg.packagesByName;
          appsModules = mod resolved.appsDir false;
          formatterModule =
            autoFormatter cfg.src pkgs mergedLib cfg.namespace inputs cfg.extraArgs
              resolved.formatterDir;
          legacyPackagesModules = mod resolved.legacyPackagesDir cfg.legacyPackagesByName;
          extraOutputs = cfg.outputsBuilder (
            cfg.extraArgs
            // {
              inherit pkgs;
              inherit (pkgs) system;
              lib = mergedLib;
              inherit inputs;
              inherit (cfg) namespace;
            }
          );
        in
        {
          _file = ./flake-module.nix;

          config = lib.recursiveUpdate (
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
            // lib.optionalAttrs (legacyPackagesModules != { }) {
              legacyPackages = legacyPackagesModules;
            }
            // lib.optionalAttrs (appsModules != { }) {
              apps = appsModules;
            }
            // lib.optionalAttrs (formatterModule != null) {
              formatter = formatterModule;
            }
          ) extraOutputs;
        };
    }
  );
}
