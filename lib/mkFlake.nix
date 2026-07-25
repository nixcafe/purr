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

  inherit (systems) defaultSystems eachSystem;

  inherit (resolveDir) resolveDirs;

  inherit (purrLib) buildImportedPurrLib mergePurrLib;

  inherit (autoMods) autoModules overlayModules templateModules;

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

      resolved = resolveDirs src {
        inherit
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

      mergedLib = mergePurrLib lib importedPurrLib namespace;

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
        outputsBuilder {
          inherit
            system
            inputs
            namespace
            ;
          lib = mergedLib;
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

      checks = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs resolved.checksDir
      );

      shells = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs resolved.shellsDir
      );

      overlays = importedOverlays;

      templates = templateModules src resolved.templatesDir templatesRecursive mergedLib namespace inputs;

      packages = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs resolved.packagesDir
      );

      apps = forAllSystems (
        system: autoModules src pkgs.${system} mergedLib namespace inputs resolved.appsDir
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
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            inputs = allInputs;
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
              namespace
              nixpkgsConfig
              sharedOverlays
              ;
            inputs = allInputs;
            extraModules = extraModulesWithLocal;
            lib = mergedLib;
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
