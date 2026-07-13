{
  attrs,
  eachSystem,
  lib,
  modules,
  namespacedModules,
  ...
}:
let
  inherit (lib)
    imap0
    ;

  inherit (attrs)
    optionalAttrs
    ;

  inherit (eachSystem)
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
        home = [
          "home"
          "shared"
        ];
      },
      extraModules ? { },
      checksDir ? null,
      shellsDir ? null,
      overlaysDir ? null,
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
              ${namespace} = import libDir { inherit lib; };
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

      channels = forAllSystems (
        system:
        let
          inherit (inputs) nixpkgs;
          pkgs = import nixpkgs {
            inherit system;
            config = channelsConfig;
            overlays = [ ];
          };
        in
        {
          inherit nixpkgs pkgs;
        }
      );

      extraOutputs = outputsBuilder (builtins.mapAttrs (_: c: c.pkgs) channels);

      checks =
        if checksDir' != null then
          forAllSystems (
            _system:
            let
              checkModules = modules.findModules src checksDir';
            in
            builtins.mapAttrs (_: import) checkModules
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
            builtins.mapAttrs (_: module: import module { pkgs = channels.${system}.pkgs; }) shellModules
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

      formatter = extraOutputs.formatter or { };
    }
    // optionalAttrs (checks != { }) { inherit checks; }
    // optionalAttrs (shells != { }) { devShells = shells; }
    // optionalAttrs (overlays != { }) { inherit overlays; }
    // builtins.removeAttrs extraOutputs [ "formatter" ];
in
{
  inherit mkFlake;
}
