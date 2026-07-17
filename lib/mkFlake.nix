{
  attrs,
  configs,
  systems,
  lib,
  modules,
  namespacedModules,
  ...
}:
let
  inherit (lib)
    concatMap
    foldl'
    imap0
    unique
    ;

  inherit (attrs)
    optionalAttrs
    ;

  inherit (systems)
    defaultSystems
    eachSystem
    ;

  mkFlake =
    {
      inputs,
      src,
      namespace ? null,
      libDir ? null,
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
      systemsDir ? null,
      homesDir ? null,
      ...
    }:
    let
      listModules =
        list:
        builtins.listToAttrs (
          imap0 (i: m: {
            name = "extra-${toString i}";
            value = m;
          }) list
        );

      forAllSystems = f: eachSystem systems f;

      modulesPath = src + "/${modulesDir}";
      allModules = modules.discoverModules modulesPath moduleTypes;

      extra = builtins.mapAttrs (_: listModules) extraModules;

      importedPurrLib =
        if libDir' != null then
          let
            rootModule =
              if builtins.pathExists (src + "/${libDir'}/default.nix") then
                import (src + "/${libDir'}/default.nix") {
                  inherit lib inputs namespace;
                }
              else
                { };
            subModules = modules.findModules src libDir';
            importedSubModules = namespacedModules.deepMapAttrs (
              path:
              import path {
                inherit lib inputs namespace;
              }
            ) subModules;
          in
          rootModule // importedSubModules
        else
          null;

      purrLib =
        if importedPurrLib != null then
          if namespace != null then lib // { ${namespace} = importedPurrLib; } else lib // importedPurrLib
        else
          lib;

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

      makeModuleSet =
        name:
        lib.recursiveUpdate (wrapWithLib (
          namespacedModules.wrapModuleSet namespace (allModules.${name} or { })
        )) (extra.${name} or { });

      makeBundled =
        name:
        let
          merged = makeModuleSet name;
        in
        if bundleModules && !(merged ? "default") then
          let
            toBundle =
              if bundleExtraModules then
                merged
              else
                wrapWithLib (namespacedModules.wrapModuleSet namespace (allModules.${name} or { }));
          in
          merged
          // {
            default = {
              imports = modules.collectModules toBundle;
            };
          }
        else
          merged;

      nixosModules = makeBundled "nixos";
      darwinModules = makeBundled "darwin";
      homeModules = makeBundled "home";

      resolve =
        dir: candidates:
        if dir != null then
          dir
        else
          let
            found = builtins.filter (d: builtins.pathExists (src + "/${d}")) candidates;
          in
          if found != [ ] then builtins.head found else null;

      checksDir' = resolve checksDir [ "checks" ];
      shellsDir' = resolve shellsDir [
        "shells"
        "devShells"
      ];
      overlaysDir' = resolve overlaysDir [ "overlays" ];
      packagesDir' = resolve packagesDir [ "packages" ];
      appsDir' = resolve appsDir [ "apps" ];
      libDir' = resolve libDir [ "lib" ];
      templatesDir' = resolve templatesDir [ "templates" ];
      systemsDir' = resolve systemsDir [
        "systems"
        "hosts"
      ];
      homesDir' = resolve homesDir [ "homes" ];

      pkgs = forAllSystems (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = nixpkgsConfig;
          overlays = [ ];
        }
      );

      perSystem = forAllSystems (
        system:
        outputsBuilder {
          inherit
            system
            inputs
            namespace
            ;
          pkgs = pkgs.${system};
          lib = purrLib;
        }
      );

      pivotedOutputs =
        let
          allKeys = unique (concatMap builtins.attrNames (builtins.attrValues perSystem));
        in
        builtins.listToAttrs (
          builtins.map (key: {
            name = key;
            value = builtins.mapAttrs (_system: outs: outs.${key}) perSystem;
          }) allKeys
        );

      autoModules =
        system: dir:
        if dir != null then
          let
            mods = modules.findModules src dir;
          in
          builtins.mapAttrs (
            _: module:
            import module {
              inherit
                inputs
                system
                namespace
                ;
              lib = purrLib;
              pkgs = pkgs.${system};
            }
          ) mods
        else
          { };

      checks = forAllSystems (system: autoModules system checksDir');

      shells = forAllSystems (system: autoModules system shellsDir');

      overlays =
        if overlaysDir' != null then
          let
            overlayModules = modules.findModules src overlaysDir';
          in
          builtins.mapAttrs (_: import) overlayModules
        else
          { };

      templates =
        if templatesDir' != null then
          let
            templateModules =
              if templatesRecursive then
                modules.findModules src templatesDir'
              else
                modules.findModulesFlat src templatesDir';
          in
          builtins.mapAttrs (
            _name: module:
            import module {
              inherit inputs namespace;
              lib = purrLib;
            }
          ) templateModules
        else
          { };

      packages = forAllSystems (system: autoModules system packagesDir');

      apps = forAllSystems (system: autoModules system appsDir');

      # -- Systems and Homes --
      discoveredSystems = if systemsDir' != null then modules.discoverSystems src systemsDir' else { };

      discoveredHomes = if homesDir' != null then modules.discoverHomes src homesDir' else { };

      buildSystemConfigs =
        if discoveredSystems != { } then
          configs.buildSystemConfigs {
            inherit
              discoveredSystems
              discoveredHomes
              inputs
              nixpkgsConfig
              ;
          }
        else
          { };

      buildHomeConfigs =
        if discoveredHomes != { } then
          configs.buildHomeConfigs {
            inherit
              discoveredHomes
              inputs
              nixpkgsConfig
              ;
          }
        else
          { };
    in
    {
      inherit
        darwinModules
        homeModules
        nixosModules
        ;

      formatter = pivotedOutputs.formatter or { };
    }
    // foldl' (acc: x: acc // x) { } [
      (optionalAttrs (checks != { }) { inherit checks; })
      (optionalAttrs (shells != { }) { devShells = shells; })
      (optionalAttrs (overlays != { }) { inherit overlays; })
      (optionalAttrs (templates != { }) { inherit templates; })
      (optionalAttrs (packages != { }) { inherit packages; })
      (optionalAttrs (apps != { }) { inherit apps; })
      (optionalAttrs (discoveredSystems != { }) buildSystemConfigs)
      (optionalAttrs (discoveredHomes != { }) { homeConfigurations = buildHomeConfigs; })
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
    ]
    // builtins.removeAttrs pivotedOutputs [ "formatter" ];
in
{
  inherit mkFlake;
}
