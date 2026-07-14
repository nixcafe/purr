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

      makeLibExtension =
        if namespace != null && libDir != null then
          {
            _module.args.lib = lib // {
              ${namespace} = import (src + "/${libDir}") { inherit lib; };
            };
          }
        else
          null;

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

      nixosModules = lib.recursiveUpdate (wrapWithLib (
        namespacedModules.wrapModuleSet namespace (allModules.nixos or { })
      )) (extra.nixos or { });
      darwinModules = lib.recursiveUpdate (wrapWithLib (
        namespacedModules.wrapModuleSet namespace (allModules.darwin or { })
      )) (extra.darwin or { });
      homeModules = lib.recursiveUpdate (wrapWithLib (
        namespacedModules.wrapModuleSet namespace (allModules.home or { })
      )) (extra.home or { });

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

      checks =
        if checksDir' != null then
          forAllSystems (
            system:
            let
              checkModules = modules.findModules src checksDir';
            in
            builtins.mapAttrs (
              _: module:
              import module {
                inherit inputs system;
              }
            ) checkModules
          )
        else
          { };

      shells =
        if shellsDir' != null then
          forAllSystems (
            system:
            let
              shellModules = modules.findModules src shellsDir';
            in
            builtins.mapAttrs (
              _: module:
              import module {
                inherit inputs system;
                pkgs = pkgs.${system};
              }
            ) shellModules
          )
        else
          { };

      overlays =
        if overlaysDir' != null then
          let
            overlayModules = modules.findModules src overlaysDir';
          in
          builtins.mapAttrs (_: import) overlayModules
        else
          { };

      packages =
        if packagesDir' != null then
          forAllSystems (
            system:
            let
              packageModules = modules.findModules src packagesDir';
            in
            builtins.mapAttrs (
              _: module:
              import module {
                inherit inputs system lib;
                pkgs = pkgs.${system};
              }
            ) packageModules
          )
        else
          { };
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
      };

      formatter = pivotedOutputs.formatter or { };
    }
    // optionalAttrs (checks != { }) { inherit checks; }
    // optionalAttrs (shells != { }) { devShells = shells; }
    // optionalAttrs (overlays != { }) { inherit overlays; }
    // optionalAttrs (packages != { }) { inherit packages; }
    // builtins.removeAttrs pivotedOutputs [ "formatter" ];
in
{
  inherit mkFlake;
}
