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
    if parts == null then
      {
        arch = null;
        format = null;
      }
    else
      {
        arch = builtins.head parts;
        format = builtins.elemAt parts 1;
      };

  parseUserHost =
    userHost:
    let
      parts = builtins.match "([^@]+)@(.*)" userHost;
    in
    if parts == null then
      {
        user = null;
        host = null;
      }
    else
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
      nixpkgsConfig ? { },
      extraModules ? { },
      autoInject ? true,
    }:
    let
      hm = inputs.home-manager or inputs.homeManager or null;
      nd = inputs.nix-darwin or inputs.darwin or null;
      hasHomeManager = hm != null;
      hasNixDarwin = nd != null;

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

              purr = {
                name = systemName;
                inherit arch archFormat format;
                homes = builtins.map (h: {
                  inherit (h) user;
                  host = systemName;
                }) matchingHomes;
              };

              hmModule =
                if format == "darwin" then hm.darwinModules.home-manager else hm.nixosModules.home-manager;
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
              systemModules = lib.optional (nixpkgsConfig != { }) {
                nixpkgs.config = mkDefault nixpkgsConfig;
              };
              extraSystemModules = extraModules.${if format == "darwin" then "darwin" else "nixos"} or [ ];

              autoInjectModules = lib.optional autoInject {
                networking.hostName = mkDefault systemName;
              };

              baseModules =
                autoInjectModules ++ systemModules ++ extraSystemModules ++ [ sysModule ] ++ homeModules;
            in
            if format == "linux" then
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = baseModules;
                specialArgs = {
                  inherit
                    inputs
                    purr
                    ;
                };
              }
            else if format == "darwin" && hasNixDarwin then
              nd.lib.darwinSystem {
                inherit system;
                modules = baseModules;
                specialArgs = {
                  inherit
                    inputs
                    purr
                    ;
                };
              }
            else
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = baseModules ++ [
                  { image.variant = format; }
                ];
                specialArgs = {
                  inherit
                    inputs
                    purr
                    ;
                };
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
      nixpkgsConfig,
      extraModules ? { },
      autoInject ? true,
    }:
    let
      hm = inputs.home-manager or inputs.homeManager or null;
    in
    if hm != null then
      builtins.listToAttrs (
        concatMap (
          archFormat:
          let
            parsed = parseArchFormat archFormat;
            inherit (parsed) arch format;
            system = if format == "darwin" then "${arch}-darwin" else "${arch}-linux";
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = nixpkgsConfig;
              overlays = [ ];
            };
          in
          builtins.map (userHost: {
            name = userHost;
            value =
              let
                hostParsed = parseUserHost userHost;
                autoInjectModules = lib.optional autoInject {
                  home.username = mkDefault hostParsed.user;
                  home.homeDirectory = mkDefault (
                    if format == "darwin" then "/Users/${hostParsed.user}" else "/home/${hostParsed.user}"
                  );
                };
              in
              hm.lib.homeManagerConfiguration {
                inherit pkgs;
                modules =
                  autoInjectModules ++ extraModules.home or [ ] ++ [ discoveredHomes.${archFormat}.${userHost} ];
                extraSpecialArgs = {
                  purr = {
                    inherit (hostParsed) user host;
                    inherit arch archFormat format;
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
    parseArchFormat
    parseUserHost
    ;
}
