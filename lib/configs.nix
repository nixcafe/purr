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

  # Auto-generated meta keys that users cannot override. If a user meta source
  # (meta.nix or hosts.<name>.meta) sets one of these, a warning is emitted and
  # the auto-generated value is kept.
  reservedMetaKeys = [
    "name"
    "arch"
    "archFormat"
    "format"
    "isDarwin"
    "isLinux"
    "system"
    "homes"
  ];

  # Resolve a host's effective meta by merging, in increasing priority:
  # auto-generated meta -> `meta.nix` next to the host's `default.nix` -> the
  # `hosts.<name>.meta` config (deep merge). `meta.nix` may be a plain attrset
  # or a function; functions are called with the auto meta plus `host`,
  # `inputs`, `lib`, `namespace`, `extraArgs` — all lazily bound, so users can
  # write cheap conditional metadata without paying for nixpkgs/system eval.
  # Reserved keys in user meta are warned about and dropped, guaranteeing the
  # auto-generated structure can never be overridden.
  buildMeta =
    {
      name,
      sysModule,
      autoMeta,
      inputs,
      lib,
      namespace,
      extraArgs,
      hostsMeta,
    }:
    let
      metaFile = builtins.dirOf sysModule + "/meta.nix";
      rawFile = if builtins.pathExists metaFile then import metaFile else { };
      computedFileMeta =
        if lib.isFunction rawFile then
          rawFile (
            autoMeta
            // {
              host = name;
              inherit
                extraArgs
                inputs
                lib
                namespace
                ;
            }
          )
        else
          rawFile;
      fileMeta =
        if builtins.isAttrs computedFileMeta then
          computedFileMeta
        else
          throw "purr: host '${name}': meta.nix must evaluate to an attrset, got '${builtins.typeOf computedFileMeta}'";
      rawUser = lib.recursiveUpdate fileMeta (hostsMeta.${name} or { });
      reservedHits = builtins.filter (k: builtins.elem k reservedMetaKeys) (builtins.attrNames rawUser);
      userMeta = lib.foldl' (
        acc: k:
        lib.warn
          "purr: host '${name}': meta key '${k}' is auto-generated and cannot be overridden; ignoring your value"
          (lib.removeAttrs acc [ k ])
      ) rawUser reservedHits;
      images =
        if userMeta ? images then
          if builtins.isList userMeta.images then
            userMeta.images
          else
            throw "purr: host '${name}': meta 'images' must be a list of strings, got '${builtins.typeOf userMeta.images}'"
        else
          [ ];
      deployable = userMeta.deployable or (images == [ ] || autoMeta.isDarwin);
    in
    {
      meta =
        autoMeta
        // userMeta
        // {
          inherit deployable images;
        };
      inherit deployable images;
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
      hostsMeta ? { },
      autoInject ? true,
      lib ? baseLib,
      sharedOverlays ? [ ],
    }:
    let
      hm = inputs.home-manager or inputs.homeManager or null;
      nd = inputs.nix-darwin or inputs.darwin or null;
      hasHomeManager = hm != null;
      hasNixDarwin = nd != null;

      knownHosts = concatMap (archFormat: builtins.attrNames (discoveredSystems.${archFormat} or { })) (
        builtins.attrNames discoveredSystems
      );

      # Fail loudly if hosts.<name>.meta refers to a host that does not exist.
      checkHostsMeta = builtins.foldl' (
        acc: name:
        if elem name knownHosts then
          acc
        else
          throw "purr: hosts.<${name}>.meta refers to no discovered system; expected a systems/<arch>-<format>/${name}/default.nix"
      ) true (builtins.attrNames hostsMeta);

      hostEntries = builtins.seq checkHostsMeta (
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

              autoMeta = {
                name = systemName;
                inherit
                  arch
                  archFormat
                  format
                  isDarwin
                  system
                  ;
                isLinux = !isDarwin;
                homes = builtins.map (h: {
                  inherit (h) user;
                  host = systemName;
                }) matchingHomes;
              };

              metaInfo = buildMeta {
                name = systemName;
                inherit
                  autoMeta
                  extraArgs
                  hostsMeta
                  inputs
                  lib
                  namespace
                  ;
                sysModule = sysModule;
              };

              inherit (metaInfo) deployable images meta;

              purr = {
                name = metaInfo.meta.name;
                inherit
                  arch
                  archFormat
                  format
                  isDarwin
                  ;
                isLinux = !isDarwin;
                inherit (metaInfo.meta) homes;
                inherit meta;
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
        ) (builtins.attrNames discoveredSystems)
      );

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
                or (throw "image format '${format}' is declared in meta images but not provided by the host config");
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
