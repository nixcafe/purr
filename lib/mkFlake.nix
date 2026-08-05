{
  attrs,
  autoMods,
  confs,
  lib,
  mods,
  nsm,
  purrLib,
  resolveDir,
  systems,
  ...
}:
let
  inherit (lib)
    concatMap
    fix
    foldl'
    imap0
    unique
    ;

  inherit (attrs) optionalAttrs;

  inherit (import ./args.nix) purrArgs;

  inherit (systems) defaultSystems eachSystem;

  inherit (resolveDir) resolveDirs;

  inherit (purrLib) buildImportedPurrLib buildMergedLib;

  inherit (autoMods)
    autoFormatter
    autoModules
    overlayModules
    templateModules
    ;

  hj = import ./hydraJobs.nix {
    inherit lib attrs;
  };

  inherit (hj) buildHydraJobs;

  mkFlake =
    {
      inputs,
      src,
      namespace ? null,
      libDir ? null,
      flattenLib ? false,
      systems ? defaultSystems,
      nixpkgsConfig ? { },
      outputsBuilder ? (_: { }),
      modulesDir ? "modules",
      moduleTypes ? {
        nixos = [
          "nixos"
          "shared"
        ];
        darwin = [
          "darwin"
          "shared"
        ];
        home = [ "home" ];
      },
      extraModules ? { },
      bundleModules ? false,
      bundleExtraModules ? true,
      checksDir ? null,
      shellsDir ? null,
      overlaysDir ? null,
      packagesDir ? null,
      appsDir ? null,
      templatesDir ? null,
      templatesRecursive ? false,
      formatterDir ? null,
      legacyPackagesDir ? null,
      legacyPackagesByName ? false,
      systemsDir ? null,
      homesDir ? null,
      autoInject ? true,
      packagesByName ? false,
      extraArgs ? { },
      hosts ? { },
      hydraJobs ? { },
      ...
    }:
    let
      hjCfg = hydraJobs;
      hjEnabled = hjCfg.enable or false;
      hjName = hjCfg.as or "hydraJobs";
      hjDir = hjCfg.dir or null;
      hjSystems = hjCfg.systems or null;
      hjInclude = hjCfg.include or null;
      hjExtra = hjCfg.extra or { };

      listModules =
        list:
        builtins.listToAttrs (
          imap0 (i: m: {
            name = "extra-${toString i}";
            value = m;
          }) list
        );

      forAllSystems = f: eachSystem systems f;

      resolved = resolveDirs src {
        inherit
          checksDir
          shellsDir
          overlaysDir
          packagesDir
          appsDir
          templatesDir
          formatterDir
          legacyPackagesDir
          systemsDir
          homesDir
          libDir
          ;
        hydraJobsDir = hjDir;
      };

      modulesPath = src + "/${modulesDir}";
      allModules = mods.discoverModules modulesPath moduleTypes;

      extra = builtins.mapAttrs (_: listModules) extraModules;

      importedOverlays = overlayModules src resolved.overlaysDir;

      sharedOverlays = builtins.attrValues importedOverlays;

      pkgs = forAllSystems (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = nixpkgsConfig;
          overlays = sharedOverlays;
        }
      );

      importedPurrLib = buildImportedPurrLib {
        inherit
          src
          namespace
          inputs
          flattenLib
          ;
        inherit (resolved) libDir;
      };

      mergedLib = buildMergedLib {
        inherit inputs;
        inherit lib;
        importedPurrLib = importedPurrLib;
        inherit namespace;
      };

      makeModuleSet = name: nsm.wrapModuleSet namespace importedPurrLib (allModules.${name} or { });

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
              if bundleModules then if bundleExtraModules then everything else authored else authored
            );
          };
        };

      nixosModules = makeBundled "nixos";
      darwinModules = makeBundled "darwin";
      homeModules = makeBundled "home";

      extraModulesWithLocal = {
        nixos = extraModules.nixos or [ ] ++ lib.optional (nixosModules ? "default") nixosModules.default;
        darwin =
          extraModules.darwin or [ ] ++ lib.optional (darwinModules ? "default") darwinModules.default;
        home = extraModules.home or [ ] ++ lib.optional (homeModules ? "default") homeModules.default;
      };

      perSystem = forAllSystems (
        system:
        outputsBuilder (
          (purrArgs {
            inherit
              extraArgs
              inputs
              namespace
              ;
            lib = mergedLib;
          })
          // {
            inherit system;
            pkgs = pkgs.${system};
          }
        )
      );

      pivotedOutputs =
        let
          allKeys = unique (concatMap builtins.attrNames (builtins.attrValues perSystem));
        in
        builtins.listToAttrs (
          builtins.map (key: {
            name = key;
            value = builtins.mapAttrs (_system: outs: outs.${key} or { }) perSystem;
          }) allKeys
        );

      checks = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs extraArgs resolved.checksDir false
      );

      shells = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs extraArgs resolved.shellsDir false
      );

      overlays = importedOverlays;

      templates =
        templateModules src resolved.templatesDir templatesRecursive mergedLib namespace inputs
          extraArgs;

      packages = forAllSystems (
        system:
        autoModules src pkgs.${system} mergedLib namespace inputs extraArgs resolved.packagesDir
          packagesByName
      );

      apps = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs extraArgs resolved.appsDir false
      );

      autoFormatterOut =
        if resolved.formatterDir != null then
          forAllSystems (
            system: autoFormatter src pkgs.${system} mergedLib namespace inputs extraArgs resolved.formatterDir
          )
        else
          { };

      legacyPackages = forAllSystems (
        system:
        autoModules src pkgs.${system} mergedLib namespace inputs extraArgs resolved.legacyPackagesDir
          legacyPackagesByName
      );

      discoveredSystems =
        if resolved.systemsDir != null then mods.discoverSystems src resolved.systemsDir else { };

      discoveredHomes =
        if resolved.homesDir != null then mods.discoverHomes src resolved.homesDir else { };

      buildSystemConfigs =
        if discoveredSystems != { } then
          confs.buildSystemConfigs {
            inherit
              autoInject
              discoveredHomes
              discoveredSystems
              extraArgs
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            hostsMeta = builtins.mapAttrs (_: v: v.meta or { }) hosts;
            inputs = inputs;
            extraModules = extraModulesWithLocal;
            lib = mergedLib;
          }
        else
          { };
      buildHomeConfigs =
        if discoveredHomes != { } then
          confs.buildHomeConfigs {
            inherit
              autoInject
              discoveredHomes
              discoveredSystems
              extraArgs
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            hostsMeta = builtins.mapAttrs (_: v: v.meta or { }) hosts;
            inputs = inputs;
            extraModules = extraModulesWithLocal;
            lib = mergedLib;
          }
        else
          { };

      # The home config's system is the arch-format directory name; carrying it
      # here lets hydraJobs group homeConfigs without forcing cfg.pkgs.system.
      homeSystems = lib.foldl' (
        acc: archFormat:
        acc // lib.mapAttrs (userHost: _: archFormat) (discoveredHomes.${archFormat} or { })
      ) { } (builtins.attrNames discoveredHomes);

      perSysForHJ = {
        inherit
          checks
          packages
          apps
          legacyPackages
          ;
        devShells = shells;
      }
      // optionalAttrs (autoFormatterOut != { }) {
        formatter = autoFormatterOut;
      };

      hydraJobsOutput =
        if hjEnabled then
          buildHydraJobs {
            inherit
              extraArgs
              inputs
              namespace
              ;
            src = src;
            inherit (resolved) hydraJobsDir;
            hydraSystems = hjSystems;
            hydraJobsInclude = hjInclude;
            hydraJobsExtra = hjExtra;
            systemPkgs = pkgs;
            perSystemOutputs = perSysForHJ;
            systemConfigs = buildSystemConfigs;
            homeConfigs = buildHomeConfigs;
            inherit homeSystems;
            lib = mergedLib;
          }
        else
          { };

      autoOutputs = {
        inherit
          darwinModules
          homeModules
          nixosModules
          ;

        formatter = autoFormatterOut // (pivotedOutputs.formatter or { });
      }
      // foldl' (acc: x: acc // x) { } [
        (optionalAttrs (checks != { }) { inherit checks; })
        (optionalAttrs (shells != { }) { devShells = shells; })
        (optionalAttrs (overlays != { }) { inherit overlays; })
        (optionalAttrs (templates != { }) { inherit templates; })
        (optionalAttrs (packages != { }) { inherit packages; })
        (optionalAttrs (legacyPackages != { }) { inherit legacyPackages; })
        (optionalAttrs (apps != { }) { inherit apps; })
        (optionalAttrs (discoveredSystems != { }) (
          lib.removeAttrs buildSystemConfigs [
            "configSystems"
            "imageRecipes"
          ]
        ))
        (optionalAttrs (discoveredSystems != { }) {
          images = confs.imagesFromConfigs (buildSystemConfigs.imageRecipes or { }) hjSystems;
        })
        (optionalAttrs (discoveredHomes != { }) { homeConfigurations = buildHomeConfigs; })
        (optionalAttrs hjEnabled { ${hjName} = hydraJobsOutput; })
        (optionalAttrs (importedPurrLib != null) (
          if namespace != null then
            {
              lib = {
                ${namespace} = importedPurrLib;
              };
            }
          else
            { lib = importedPurrLib; }
        ))
      ];
    in
    lib.recursiveUpdate autoOutputs (builtins.removeAttrs pivotedOutputs [ "formatter" ]);
in
{
  inherit mkFlake;
}
