{
  attrs,
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
    eachDefaultSystem
    eachSystem
    ;

  mkFlake =
    {
      inputs,
      src,
      namespace ? null,
      libDir ? null,
      systems ? defaultSystems,
      channelsConfig ? { },
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
      checksDir ? null,
      shellsDir ? null,
      overlaysDir ? null,
      packagesDir ? null,
      appsDir ? null,
      ...
    }@args:
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
                import (src + "/${libDir'}/default.nix") { inherit lib; }
              else
                { };
            subModules = modules.findModules src libDir';
            importedSubModules = namespacedModules.deepMapAttrs (path: import path { inherit lib; }) subModules;
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

      nixosModules = makeModuleSet "nixos";
      darwinModules = makeModuleSet "darwin";
      homeModules = makeModuleSet "home";

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

      pkgs = forAllSystems (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = channelsConfig;
          overlays = [ ];
        }
      );

      perSystem = forAllSystems (
        system:
        outputsBuilder {
          inherit system;
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

      packages = forAllSystems (system: autoModules system packagesDir');

      apps = forAllSystems (system: autoModules system appsDir');
    in
    {
      inherit
        darwinModules
        homeModules
        nixosModules
        ;

      lib = {
        inherit
          defaultSystems
          eachDefaultSystem
          eachSystem
          ;
        mkFlake = mkFlake args;
      }
      // optionalAttrs (importedPurrLib != null) (
        if namespace != null then { ${namespace} = importedPurrLib; } else importedPurrLib
      );

      formatter = pivotedOutputs.formatter or { };
    }
    // foldl' (acc: x: acc // x) { } [
      (optionalAttrs (checks != { }) { inherit checks; })
      (optionalAttrs (shells != { }) { devShells = shells; })
      (optionalAttrs (overlays != { }) { inherit overlays; })
      (optionalAttrs (packages != { }) { inherit packages; })
      (optionalAttrs (apps != { }) { inherit apps; })
    ]
    // builtins.removeAttrs pivotedOutputs [ "formatter" ];
in
{
  inherit mkFlake;
}
