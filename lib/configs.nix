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
    listToAttrs
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

  # Options needed to decide how a host is exposed, declared both inside the
  # real system (so users can set them) and in a minimal module set used for
  # cheap pre-evaluation.
  purrMetaOptions = {
    options.purr.images = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Image formats to build for this host via Hydra CI.
        Each format maps to `config.system.build.images.<name>`.
        Supported formats include iso, qemu, raw, sd-card, amazon, etc.
      '';
    };

    options.purr.deployable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this host is a deployable system exposed as a
        `nixosConfigurations`/`darwinConfigurations` output. Hosts that set
        `purr.images` are treated as image-only recipes by default (e.g. an
        ISO builder with no root file system): they are excluded from
        `nixosConfigurations`/`darwinConfigurations` and from `hydraJobs`
        config groups, so their `system.build.toplevel` is never evaluated.
        Set this to `true` to also expose such a host as a deployable
        configuration while still building its images.
      '';
    };
  };

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

      hostEntries = concatMap (
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
          isDarwin = lib.hasSuffix "darwin" archFormat;
          extraSystemModules = extraModules.${if format == "darwin" then "darwin" else "nixos"} or [ ];
        in
        builtins.map (
          systemName:
          let
            sysModule = discoveredSystems.${archFormat}.${systemName};
            matchingHomes = if hasHomeManager then findMatchingHomes discoveredHomes systemName else [ ];

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

            # Cheap metadata read: import the host's own module file and, if it
            # is a function, call it with placeholder args so that only the
            # `purr.images` / `purr.deployable` attributes are forced. nixpkgs,
            # home-manager, nix-darwin and the rest of the system are never
            # evaluated, so image-only hosts cost (almost) nothing to expose.
            # The `purr.users` bridge and all other config stay lazy here and
            # are never evaluated. Placeholder `pkgs`/`config` are only forced
            # if a host's purr.images / purr.deployable depend on them, which
            # is an unsupported edge case.
            rawModule = import sysModule;
            hostModule =
              if lib.isFunction rawModule then
                rawModule (
                  extraArgs
                  // {
                    inherit
                      inputs
                      lib
                      namespace
                      purr
                      system
                      ;
                    host = systemName;
                    config = { };
                    pkgs = { };
                    options = { };
                    _module = { };
                  }
                )
              else
                rawModule;
            images = hostModule.purr.images or [ ];
            deployable = (hostModule.purr.deployable or false) || images == [ ] || isDarwin;

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
                              # Expose the user as a module arg and auto-inject
                              # username/home (mirrors the standalone
                              # `homeConfigurations` path in `buildHomeConfigs`).
                              {
                                _module.args.user = h.user;
                                home.username = mkDefault h.user;
                                home.homeDirectory = mkDefault (if isDarwin then "/Users/${h.user}" else "/home/${h.user}");
                              }
                              h.path
                            ];
                          };
                        }) matchingHomes
                      );
                    }
                  )
                ]
                ++ lib.optional (format == "linux" && nonRootHomes != [ ]) {
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
              purrMetaOptions
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
            ];
            autoInjectModules = lib.optional autoInject {
              networking.hostName = mkDefault systemName;
            };

            baseModules =
              autoInjectModules ++ systemModules ++ extraSystemModules ++ [ sysModule ] ++ homeModules;
            value =
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
          in
          {
            inherit
              deployable
              images
              outputKey
              system
              systemName
              value
              ;
          }
        ) (builtins.attrNames systems)
      ) (builtins.attrNames discoveredSystems);

      deployableEntries = builtins.filter (e: e.deployable) hostEntries;

      configs = mapAttrs (
        _outputKey: entries:
        listToAttrs (
          builtins.map ({ systemName, value, ... }: {
            name = systemName;
            inherit value;
          }) entries
        )
      ) (groupBy ({ outputKey, ... }: outputKey) deployableEntries);

      # host -> system, so hydraJobs can group configs by system without
      # forcing `cfg.pkgs` (reading cfg.pkgs.system evaluates nixpkgs/stdenv
      # just to obtain a string that is already known here).
      configSystems = mapAttrs (
        _outputKey: entries:
        listToAttrs (
          builtins.map ({ systemName, system, ... }: {
            name = systemName;
            value = system;
          }) entries
        )
      ) (groupBy ({ outputKey, ... }: outputKey) deployableEntries);
    in
    configs
    // {
      inherit configSystems;

      imageRecipes = listToAttrs (
        builtins.map (e: {
          name = e.systemName;
          value = {
            inherit (e) system images;
            cfg = e.value;
          };
        }) (builtins.filter (e: e.images != [ ] && e.outputKey == "nixosConfigurations") hostEntries)
      );
    };

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
    imageRecipes: systems:
    let
      filtered =
        if systems == null then
          imageRecipes
        else
          filterAttrs (_: recipe: elem recipe.system systems) imageRecipes;

      # Build the structure from the *declared* formats (recipe.images) so that
      # enumerating image jobs does not force the host's system config. The
      # existence check is deferred to the leaf, which is only evaluated when
      # that specific image is requested.
      scanHost =
        _host: recipe:
        foldl' (
          acc: format:
          acc
          // {
            ${format} =
              recipe.cfg.config.system.build.images.${format}
                or (throw "image format '${format}' is declared in purr.images but not provided by the host config");
          }
        ) { } recipe.images;
    in
    filterAttrs (_: v: v != { }) (builtins.mapAttrs scanHost filtered);
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
