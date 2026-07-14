{
  lib,
  ...
}:
let
  inherit (lib) concatMap;

  parseArchFormat =
    archFormat:
    let
      parts = builtins.match "([^-]+)-(.*)" archFormat;
    in
    {
      arch = builtins.head parts;
      format = builtins.elemAt parts 1;
    };

  parseUserHost =
    userHost:
    let
      parts = builtins.match "([^@]+)@(.*)" userHost;
    in
    {
      user = builtins.head parts;
      host = builtins.elemAt parts 1;
    };

  formatOutputKey =
    format:
    if format == "linux" then
      "nixosConfigurations"
    else if format == "darwin" then
      "darwinConfigurations"
    else
      "${format}Configurations";

  findMatchingHomes =
    discoveredHomes: hostName:
    concatMap (
      dArch:
      let
        homes = discoveredHomes.${dArch} or { };
        matches = builtins.filter (d: (parseUserHost d).host == hostName) (builtins.attrNames homes);
      in
      builtins.map (d: {
        inherit (parseUserHost d) user;
        path = homes.${d};
      }) matches
    ) (builtins.attrNames discoveredHomes);

  buildSystemConfigs =
    {
      discoveredSystems,
      discoveredHomes,
      inputs,
    }:
    let
      hasHomeManager = inputs ? home-manager;
    in
    builtins.listToAttrs (
      concatMap (
        archFormat:
        let
          parsed = parseArchFormat archFormat;
          inherit (parsed) arch format;
          systems = discoveredSystems.${archFormat};
          outputKey = formatOutputKey format;
          system = if format == "darwin" then "${arch}-darwin" else "${arch}-linux";
        in
        builtins.map (systemName: {
          name = "${outputKey}.${systemName}";
          value =
            let
              sysModule = discoveredSystems.${archFormat}.${systemName};
              matchingHomes = if hasHomeManager then findMatchingHomes discoveredHomes systemName else [ ];
              homeModules =
                if matchingHomes != [ ] then
                  [
                    inputs.home-manager.nixosModules.home-manager
                    {
                      home-manager.useGlobalPkgs = lib.mkDefault true;
                      home-manager.useUserPackages = lib.mkDefault true;
                      home-manager.users = builtins.listToAttrs (
                        builtins.map (h: {
                          name = h.user;
                          value = {
                            imports = [ h.path ];
                          };
                        }) matchingHomes
                      );
                    }
                  ]
                else
                  [ ];
              baseModules = [ sysModule ] ++ homeModules;
            in
            if format == "linux" then
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = baseModules;
              }
            else if format == "darwin" && inputs ? nix-darwin then
              inputs.nix-darwin.lib.darwinSystem {
                inherit system;
                modules = baseModules;
              }
            else
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = baseModules ++ [
                  { image.variant = format; }
                ];
              };
        }) (builtins.attrNames systems)
      ) (builtins.attrNames discoveredSystems)
    );

  buildHomeConfigs =
    {
      discoveredHomes,
      inputs,
      channelsConfig,
    }:
    if inputs ? home-manager then
      builtins.listToAttrs (
        concatMap (
          archFormat:
          let
            parsed = parseArchFormat archFormat;
            system = if parsed.format == "darwin" then "${parsed.arch}-darwin" else "${parsed.arch}-linux";
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = channelsConfig;
              overlays = [ ];
            };
          in
          builtins.map (userHost: {
            name = userHost;
            value = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [ discoveredHomes.${archFormat}.${userHost} ];
            };
          }) (builtins.attrNames discoveredHomes.${archFormat} or { })
        ) (builtins.attrNames discoveredHomes)
      )
    else
      { };
in
{
  inherit
    buildHomeConfigs
    buildSystemConfigs
    ;
}
