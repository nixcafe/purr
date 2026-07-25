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
    fix
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
      systemsDir ? null,
      homesDir ? null,
      autoInject ? true,
      ...
    }:
    let
      allInputs =
        inputs
        // builtins.foldl' (
          acc: input:
          let
            transitive = builtins.filter (k: !(acc ? ${k})) (builtins.attrNames (input.inputs or { }));
          in
          acc
          // builtins.listToAttrs (
            builtins.map (k: {
              name = k;
              value = input.inputs.${k};
            }) transitive
          )
        ) { } (builtins.attrValues inputs);

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

      importedOverlays =
        if overlaysDir' != null then
          let
            overlayModules = modules.findModulesFlat src overlaysDir';
            normalizeOverlay =
              fn: final: prev:
              let
                result = fn final prev;
              in
              if builtins.isFunction result then result prev else result;
          in
          builtins.mapAttrs (_: path: normalizeOverlay (import path)) overlayModules
        else
          { };

      sharedOverlays = builtins.attrValues importedOverlays;

      pkgs = forAllSystems (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = nixpkgsConfig;
          overlays = sharedOverlays;
        }
      );

      importedPurrLib =
        if libDir' != null then
          fix (
            self:
            let
              mergedLib =
                # Merge input libs into the base lib (skip nixpkgs-style libs)
                builtins.foldl' (
                  acc: input:
                  let
                    inputLib = input.lib or { };
                  in
                  if inputLib ? types then
                    let
                      extras = builtins.removeAttrs inputLib [
                        "types"
                        "nixos"
                        "nixosSystem"
                        "nixosOptionsDoc"
                        "nixosModules"
                        "nixosTests"
                        "systems"
                      ];
                    in
                    acc // extras
                  else
                    acc // inputLib
                ) lib (builtins.attrValues inputs);

              rootModule =
                if builtins.pathExists (src + "/${libDir'}/default.nix") then
                  import (src + "/${libDir'}/default.nix") {
                    inherit inputs namespace;
                    lib = mergedLib // (optionalAttrs (namespace != null) { ${namespace} = self; });
                  }
                else
                  { };

              subModules = modules.findModulesLib src libDir';
              importedSubModules = namespacedModules.deepMapAttrs (
                path:
                import path {
                  inherit inputs namespace;
                  lib = mergedLib // (optionalAttrs (namespace != null) { ${namespace} = self; });
                }
              ) subModules;

              nested = rootModule // importedSubModules;

              flatMerge =
                let
                  collectLeaf =
                    v:
                    if builtins.isAttrs v then
                      let
                        direct = v."default.nix" or null;
                        rest = builtins.removeAttrs v [ "default.nix" ];
                        sub = lib.concatMap collectLeaf (builtins.attrValues rest);
                      in
                      (if direct != null then [ direct ] else [ ]) ++ sub
                    else
                      [ ];
                in
                lib.foldl' (a: b: a // b) rootModule (collectLeaf importedSubModules);
            in
            if flattenLib then flatMerge else nested
          )
        else
          null;

      mergedInputLibs = builtins.foldl' (
        acc: input:
        let
          inputLib = input.lib or { };
        in
        if inputLib ? types then
          let
            extras = builtins.removeAttrs inputLib [
              "types"
              "nixos"
              "nixosSystem"
              "nixosOptionsDoc"
              "nixosModules"
              "nixosTests"
              "systems"
            ];
          in
          acc // extras
        else
          acc // inputLib
      ) lib (builtins.attrValues inputs);

      purrLib =
        if importedPurrLib != null then
          if namespace != null then
            mergedInputLibs // { ${namespace} = importedPurrLib; }
          else
            mergedInputLibs // importedPurrLib
        else
          mergedInputLibs;

      makeModuleSet = name: namespacedModules.wrapModuleSet namespace (allModules.${name} or { });

      makeBundled =
        name:
        let
          authored = makeModuleSet name;
          everything = lib.recursiveUpdate authored (extra.${name} or { });
        in
        authored
        // lib.optionalAttrs (!(everything ? "default")) {
          default = {
            imports = modules.collectModules (
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
        outputsBuilder {
          inherit
            system
            inputs
            namespace
            ;
          lib = purrLib;
          pkgs = pkgs.${system};
        }
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

      autoModules =
        system: dir:
        if dir != null then
          let
            mods = modules.findModulesFlat src dir;
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

      overlays = importedOverlays;

      templates =
        if templatesDir' != null then
          let
            templateModules =
              if templatesRecursive then
                modules.findModulesLib src templatesDir'
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
              autoInject
              discoveredSystems
              discoveredHomes
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            inputs = allInputs;
            extraModules = extraModulesWithLocal;
            lib = purrLib;
          }
        else
          { };

      buildHomeConfigs =
        if discoveredHomes != { } then
          configs.buildHomeConfigs {
            inherit
              autoInject
              discoveredHomes
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            inputs = allInputs;
            extraModules = extraModulesWithLocal;
            lib = purrLib;
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
