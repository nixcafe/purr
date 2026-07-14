{
  lib,
  ...
}:
let
  inherit (lib)
    concatMap
    groupBy
    mapAttrs
    mkDefault
    ;

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
      hasNixDarwin = inputs ? nix-darwin;

      allEntries = concatMap (
        archFormat:
        let
          parsed = parseArchFormat archFormat;
          inherit (parsed) arch format;
          systems = discoveredSystems.${archFormat};
          outputKey = formatOutputKey format;
          system = if format == "darwin" then "${arch}-darwin" else "${arch}-linux";
        in
        builtins.map (systemName: {
          inherit outputKey systemName;
          value =
            let
              sysModule = discoveredSystems.${archFormat}.${systemName};
              matchingHomes = if hasHomeManager then findMatchingHomes discoveredHomes systemName else [ ];
              hmModule =
                if format == "darwin" then
                  inputs.home-manager.darwinModules.home-manager
                else
                  inputs.home-manager.nixosModules.home-manager;
              nonRootHomes = builtins.filter (h: h.user != "root") matchingHomes;
              homeModules =
                if matchingHomes != [ ] then
                  [
                    hmModule
                    {
                      home-manager.useGlobalPkgs = mkDefault true;
                      home-manager.useUserPackages = mkDefault true;
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
                  ++ lib.optional (nonRootHomes != [ ]) {
                    users.users = builtins.listToAttrs (
                      builtins.map (h: {
                        name = h.user;
                        value = {
                          isNormalUser = mkDefault true;
                        };
                      }) nonRootHomes
                    );
                  }
                else
                  [ ];
              baseModules = [ sysModule ] ++ homeModules;
            in
            if format == "linux" then
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = baseModules;
              }
            else if format == "darwin" && hasNixDarwin then
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
      ) (builtins.attrNames discoveredSystems);

      grouped = groupBy ({ outputKey, ... }: outputKey) allEntries;
    in
    mapAttrs (
      _outputKey: entries:
      builtins.listToAttrs (
        builtins.map ({ systemName, value, ... }: {
          name = systemName;
          inherit value;
        }) entries
      )
    ) grouped;

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
            value =
              let
                parsed = parseUserHost userHost;
              in
              inputs.home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                modules = [ discoveredHomes.${archFormat}.${userHost} ];
                extraSpecialArgs = {
                  purr = {
                    inherit (parsed) user host;
                  };
                };
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
