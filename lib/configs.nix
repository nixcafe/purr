{
  lib,
  ...
}:
let
  inherit (lib)
    concatMap
    elem
    filterAttrs
    foldl'
    groupBy
    mapAttrs
    mkDefault
    ;

  baseLib = lib;

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
      throw "unsupported format '${format}': purr only supports 'linux' and 'darwin'. Put your system configs under systems/<arch>-linux/ or systems/<arch>-darwin/.";

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
      namespace ? null,
      nixpkgsConfig ? { },
      extraModules ? { },
      extraArgs ? { },
      autoInject ? true,
      lib ? baseLib,
      sharedOverlays ? [ ],
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
          system =
            if format == "darwin" then
              "${arch}-darwin"
            else if format == "linux" then
              "${arch}-linux"
            else
              throw "unsupported format '${format}' in systems directory: purr only supports 'linux' and 'darwin'. Put your system configs under systems/<arch>-linux/ or systems/<arch>-darwin/.";
          systems = discoveredSystems.${archFormat};
          outputKey = formatOutputKey format;
        in
        builtins.map (systemName: {
          inherit outputKey systemName;
          value =
            let
              sysModule = discoveredSystems.${archFormat}.${systemName};
              matchingHomes = if hasHomeManager then findMatchingHomes discoveredHomes systemName else [ ];

              isDarwin = lib.hasSuffix "darwin" archFormat;

              purr = {
                name = systemName;
                inherit
                  arch
                  archFormat
                  format
                  isDarwin
                  ;
                isLinux = !isDarwin;
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
                    {
                      options.purr.users = lib.mkOption {
                        type = lib.types.attrs;
                        default = { };
                        description = ''
                          Per-user home-manager config forwarded via namespace bridge.
                          Set `purr.users.<name>.homeConfig = { ... }` from any
                          NixOS module to inject home-manager settings for that
                          user.  Keys inside `homeConfig` map directly to
                          home-manager option paths (home.packages, programs.*,
                          services.*, etc.).
                        '';
                      };
                    }
                  ]
                  ++ [
                    hmModule
                    (
                      {
                        config,
                        lib,
                        ...
                      }:
                      let
                        nsUsers = config.purr.users or { };
                      in
                      {
                        home-manager.useGlobalPkgs = mkDefault true;
                        home-manager.useUserPackages = mkDefault true;
                        home-manager.extraSpecialArgs = extraArgs // {
                          inherit
                            inputs
                            namespace
                            purr
                            system
                            ;
                          purrLib = lib;
                          host = systemName;
                        };
                        home-manager.users = builtins.listToAttrs (
                          builtins.map (h: {
                            name = h.user;
                            value = {
                              imports = extraModules.home or [ ] ++ [
                                # Bridge: forward <ns>.users.<name>.homeConfig as
                                # home-manager defaults.  Placed before h.path
                                # so the home module takes priority.
                                {
                                  config = nsUsers.${h.user}.homeConfig or { };
                                }
                                h.path
                              ];
                            };
                          }) matchingHomes
                        );
                      }
                    )
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
              systemModules = [
                {
                  nixpkgs.config = mkDefault nixpkgsConfig;
                  nixpkgs.overlays = mkDefault sharedOverlays;
                }
                {
                  options.nixpkgs.system = lib.mkOption {
                    type = lib.types.str;
                    internal = true;
                    visible = false;
                  };
                }
                {
                  options.purr.images = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = ''
                      Image formats to build for this host via Hydra CI.
                      Each format maps to `config.system.build.images.<name>`.
                      Supported formats include iso, qemu, raw, sd-card, amazon, etc.
                    '';
                  };
                }
              ];
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
                specialArgs = extraArgs // {
                  inherit
                    inputs
                    lib
                    namespace
                    purr
                    system
                    ;
                  host = systemName;
                };
              }
            else if format == "darwin" then
              if hasNixDarwin then
                nd.lib.darwinSystem {
                  inherit system;
                  modules = baseModules;
                  specialArgs = extraArgs // {
                    inherit
                      inputs
                      lib
                      namespace
                      purr
                      system
                      ;
                    host = systemName;
                  };
                }
              else
                throw "darwin system '${systemName}' requires nix-darwin input (add inputs.nix-darwin or inputs.darwin to your flake)"
            else
              throw "unsupported format '${format}' for system '${systemName}'";
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
      namespace ? null,
      nixpkgsConfig ? { },
      extraModules ? { },
      extraArgs ? { },
      autoInject ? true,
      lib ? baseLib,
      sharedOverlays ? [ ],
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
            system =
              if format == "darwin" then
                "${arch}-darwin"
              else if format == "linux" then
                "${arch}-linux"
              else
                throw "unsupported format '${format}' in homes directory: purr only supports 'linux' and 'darwin'.";
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = nixpkgsConfig;
              overlays = sharedOverlays;
            };
          in
          builtins.map (userHost: {
            name = userHost;
            value =
              let
                hostParsed = parseUserHost userHost;
                isDarwin = lib.hasSuffix "darwin" archFormat;
                autoInjectModules = lib.optional autoInject {
                  home.username = mkDefault hostParsed.user;
                  home.homeDirectory = mkDefault (
                    if isDarwin then "/Users/${hostParsed.user}" else "/home/${hostParsed.user}"
                  );
                };
              in
              hm.lib.homeManagerConfiguration {
                inherit pkgs;
                modules =
                  autoInjectModules ++ extraModules.home or [ ] ++ [ discoveredHomes.${archFormat}.${userHost} ];
                extraSpecialArgs = extraArgs // {
                  inherit
                    inputs
                    namespace
                    system
                    ;
                  inherit (hostParsed) host user;
                  purrLib = lib;
                  purr = {
                    inherit (hostParsed) user host;
                    inherit
                      arch
                      archFormat
                      format
                      isDarwin
                      ;
                    isLinux = !isDarwin;
                  };
                };
              };
          }) (builtins.attrNames discoveredHomes.${archFormat} or { })
        ) (builtins.attrNames discoveredHomes)
      )
    else
      { };
  imagesFromConfigs =
    systemConfigs: systems:
    let
      nixosConfigs = systemConfigs.nixosConfigurations or { };

      filteredConfigs =
        if systems == null then
          nixosConfigs
        else
          filterAttrs (
            _host: cfg:
            let
              sys = cfg.pkgs.system or null;
            in
            sys != null && elem sys systems
          ) nixosConfigs;

      scanHost =
        _host: cfg:
        let
          imagesExists = cfg.config.system ? build && cfg.config.system.build ? images;
          purrImages = if cfg.config ? purr && cfg.config.purr ? images then cfg.config.purr.images else [ ];
        in
        if imagesExists && purrImages != [ ] then
          let
            images = cfg.config.system.build.images;
          in
          foldl' (
            acc: format: if images ? ${format} then acc // { ${format} = images.${format}; } else acc
          ) { } purrImages
        else
          { };
    in
    filterAttrs (_: v: v != { }) (builtins.mapAttrs scanHost filteredConfigs);
in
{
  inherit
    buildHomeConfigs
    buildSystemConfigs
    findMatchingHomes
    formatOutputKey
    imagesFromConfigs
    parseArchFormat
    parseUserHost
    ;
}
