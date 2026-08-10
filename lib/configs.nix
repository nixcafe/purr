{
  lib,
  mergePurrLib ? (
    lib': importedPurrLib: namespace:
    if importedPurrLib != null then
      lib'.extend (
        _self: _super: if namespace != null then { ${namespace} = importedPurrLib; } else importedPurrLib
      )
    else
      lib'
  ),
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

  inherit (import ./args.nix) purrArgs;

  inherit (import ./resolveInput.nix) defaultHomeManager defaultNixDarwin resolveRole;

  # The internal inputs purr actually builds with. Defaults to the raw flake
  # inputs when no `inputsFor` transform is in play (mkFlake always passes the
  # computed effective inputs; direct builder callers can omit it).
  withEffective =
    inputs: effectiveInputs: if effectiveInputs == null then inputs else effectiveInputs;

  # Meta key under which per-host input role overrides live. Nested under its
  # own key so the role names (nixpkgs, home-manager, nix-darwin) never collide
  # with a host's free-form custom meta keys.
  rolesKey = "roles";

  # Effective-input key for a host role: `meta.<rolesKey>.<role>` when set,
  # else the conventional default.
  roleKey =
    meta: role: default:
    meta.${rolesKey}.${role} or default;

  # The merged lib handed to a host's modules. Its base is that host's
  # effective nixpkgs lib (real nixpkgs libs expose `attrNames`) re-merged with
  # the flake's namespace lib, so a host that switched nixpkgs gets matching
  # lib-derived metadata (`system.nixos.revision`, ...). Falls back to the
  # caller-provided merged lib when the host's nixpkgs is missing or is a mock.
  perHostLib =
    {
      effectiveInputs,
      meta,
      importedPurrLib,
      namespace,
      lib,
    }:
    let
      key = roleKey meta "nixpkgs" "nixpkgs";
      nixpkgsLib = if effectiveInputs ? ${key} then effectiveInputs.${key}.lib or null else null;
    in
    if nixpkgsLib != null && nixpkgsLib ? attrNames then
      mergePurrLib nixpkgsLib importedPurrLib namespace
    else
      lib;

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
    "host"
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

  # Build the per-host metadata registry. Pure metadata only — it never
  # touches system config `value`s, so it is cycle-free and safe to build
  # independently from the configs themselves (and reusable by home configs).
  #
  # Returns:
  #   - `hostMeta`: list of per-host records containing the system string,
  #     output key, arch/format info, `deployable`/`images` and the merged
  #     `meta`.
  #   - `registry`: `name -> meta` for every discovered host, used as
  #     `purr.systemMetas`.
  buildSystemRegistry =
    {
      discoveredSystems,
      discoveredHomes,
      inputs,
      effectiveInputs ? null,
      namespace ? null,
      extraArgs ? { },
      hostsMeta ? { },
      lib ? baseLib,
    }:
    let
      einputs = withEffective inputs effectiveInputs;
      hm = einputs.home-manager or einputs.homeManager or null;
      hasHomeManager = hm != null;

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

      hostMeta = builtins.seq checkHostsMeta (
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
            isDarwin = lib.hasSuffix "darwin" archFormat;
            outputKey = formatOutputKey format;
          in
          builtins.map (
            systemName:
            let
              sysModule = discoveredSystems.${archFormat}.${systemName};
              matchingHomes = if hasHomeManager then findMatchingHomes discoveredHomes systemName else [ ];

              autoMeta = {
                name = systemName;
                host = systemName;
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
            in
            {
              inherit
                arch
                archFormat
                deployable
                format
                images
                isDarwin
                matchingHomes
                meta
                outputKey
                system
                systemName
                ;
            }
          ) (builtins.attrNames systems)
        ) (builtins.attrNames discoveredSystems)
      );

      registry = listToAttrs (
        builtins.map (e: {
          name = e.systemName;
          value = e.meta;
        }) hostMeta
      );
    in
    {
      inherit hostMeta registry;
    };

  # The lib handed to home-manager modules. Starts from the merged lib and
  # re-adds home-manager's own `hm` extension, since home-manager evaluates
  # with its own extended lib as `lib`. Built via `extend` (not `//`) so the
  # merged namespace lib and `hm` survive further `extend`s — home-manager's
  # manual/docs path extends the module lib again, and a plain `//` merged lib
  # would silently drop both, breaking `lib.hm` inside the docs evaluation.
  homeLibFor =
    hm: lib':
    lib'.extend (
      _self: _super: {
        hm = hm.lib.hm or { };
      }
    );

  buildSystemConfigs =
    {
      discoveredSystems,
      discoveredHomes,
      inputs,
      effectiveInputs ? null,
      namespace ? null,
      nixpkgsConfig ? { },
      extraModules ? { },
      extraArgs ? { },
      hostsMeta ? { },
      autoInject ? true,
      lib ? baseLib,
      importedPurrLib ? null,
      sharedOverlays ? [ ],
    }:
    let
      einputs = withEffective inputs effectiveInputs;

      registryInfo = buildSystemRegistry {
        inherit
          discoveredHomes
          discoveredSystems
          effectiveInputs
          extraArgs
          hostsMeta
          inputs
          lib
          namespace
          ;
      };
      inherit (registryInfo) hostMeta registry;

      # Second pass: build the actual system config values. Reads only metadata
      # from `hostMeta` plus the registry for `purr.systemMetas` — no cycles.
      hostEntries = builtins.map (
        {
          arch,
          archFormat,
          deployable,
          format,
          images,
          isDarwin,
          matchingHomes,
          meta,
          outputKey,
          system,
          systemName,
          ...
        }:
        let
          sysModule = discoveredSystems.${archFormat}.${systemName};

          purr = {
            inherit meta;
            systemMetas = registry;
          };

          # Resolve this host's effective inputs for the roles purr consumes.
          # `meta.<role>` wins when set; otherwise the conventional key from
          # the effective inputs (the `inputsFor` result) is used.
          nixpkgsInput = resolveRole {
            effectiveInputs = einputs;
            key = roleKey meta "nixpkgs" "nixpkgs";
            context = "host '${systemName}'";
          };
          ndKey = roleKey meta "nix-darwin" (defaultNixDarwin einputs);
          ndInput =
            if ndKey == null then
              null
            else
              resolveRole {
                effectiveInputs = einputs;
                key = ndKey;
                context = "host '${systemName}'";
              };
          hmKey = roleKey meta "home-manager" (defaultHomeManager einputs);
          hmInput =
            if hmKey == null then
              null
            else
              resolveRole {
                effectiveInputs = einputs;
                key = hmKey;
                context = "host '${systemName}'";
              };
          # The lib handed to this host's modules follows the host's own
          # nixpkgs (so lib-derived metadata matches), not the global default.
          hostLib = perHostLib {
            effectiveInputs = einputs;
            inherit importedPurrLib namespace;
            inherit meta;
            inherit lib;
          };
          homeLib = if hmInput != null then homeLibFor hmInput hostLib else null;

          hmModule =
            if format == "darwin" then
              hmInput.darwinModules.home-manager
            else
              hmInput.nixosModules.home-manager;
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
                    # NOTE: do NOT set `lib = homeLib` here. Home-manager's
                    # NixOS module evaluates bridged homes through
                    # `types.submoduleWith`; overriding `lib` via
                    # extraSpecialArgs breaks its internal module evaluation
                    # (e.g. `lib.hm` goes missing during option collection).
                    # Bridged homes keep home-manager's own extended lib; the
                    # merged namespace lib is exposed via `purr.lib` instead.
                    #
                    # TODO: home-manager upstream regression — once
                    # submoduleWith + `lib` override stops breaking internal
                    # module collection, bridged homes can get `lib =
                    # homeLib` directly and `purr.lib` can be dropped.
                    home-manager.extraSpecialArgs = extraArgs // {
                      inherit
                        inputs
                        namespace
                        system
                        ;
                      host = systemName;
                      # Bridged homes get the host's purr, plus a
                      # `systemMeta` back-link (so the same home module file
                      # works both standalone and linked to a system) and the
                      # merged namespace lib as `purr.lib`.
                      purr = purr // {
                        systemMeta = purr.meta;
                        lib = homeLib;
                      };
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
          # Inject at default priority (not mkDefault): nixpkgs.config and
          # nixpkgs.overlays both use merge-friendly types (deep merge / list
          # concat), so a host/home module's own plain `nixpkgs.overlays` or
          # `nixpkgs.config` at the same priority MERGES with these instead of
          # silently replacing them. Use mkForce to fully replace.
          systemModules = [
            {
              nixpkgs.config = nixpkgsConfig;
              nixpkgs.overlays = sharedOverlays;
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
          extraSystemModules = extraModules.${if format == "darwin" then "darwin" else "nixos"} or [ ];

          baseModules =
            autoInjectModules ++ systemModules ++ extraSystemModules ++ [ sysModule ] ++ homeModules;
          value =
            if format == "linux" then
              nixpkgsInput.lib.nixosSystem {
                inherit system;
                modules = baseModules;
                specialArgs =
                  (purrArgs {
                    inherit
                      extraArgs
                      inputs
                      namespace
                      ;
                    lib = hostLib;
                  })
                  // {
                    inherit
                      purr
                      system
                      ;
                    host = systemName;
                  };
              }
            else if format == "darwin" then
              if ndInput != null then
                ndInput.lib.darwinSystem {
                  inherit system;
                  modules = baseModules;
                  specialArgs =
                    (purrArgs {
                      inherit
                        extraArgs
                        inputs
                        namespace
                        ;
                      lib = hostLib;
                    })
                    // {
                      inherit
                        purr
                        system
                        ;
                      host = systemName;
                    };
                }
              else
                throw "darwin system '${systemName}' requires a nix-darwin input (add inputs.nix-darwin or inputs.darwin, or set meta.roles.nix-darwin)"
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
      ) hostMeta;

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
      discoveredSystems ? { },
      inputs,
      effectiveInputs ? null,
      namespace ? null,
      nixpkgsConfig ? { },
      extraModules ? { },
      extraArgs ? { },
      hostsMeta ? { },
      autoInject ? true,
      lib ? baseLib,
      importedPurrLib ? null,
      sharedOverlays ? [ ],
    }:
    let
      einputs = withEffective inputs effectiveInputs;
      hm = einputs.home-manager or einputs.homeManager or null;
    in
    if hm != null then
      let
        registryInfo = buildSystemRegistry {
          inherit
            discoveredHomes
            discoveredSystems
            effectiveInputs
            extraArgs
            hostsMeta
            inputs
            lib
            namespace
            ;
        };
        inherit (registryInfo) registry;
      in
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
          in
          builtins.map (userHost: {
            name = userHost;
            value =
              let
                hostParsed = parseUserHost userHost;
                isDarwin = lib.hasSuffix "darwin" archFormat;
                systemMeta = registry.${hostParsed.host} or null;
                # A home inherits its linked system's nixpkgs role; without a
                # matching system it falls back to the effective-input default.
                nixpkgsInput = resolveRole {
                  effectiveInputs = einputs;
                  key = roleKey systemMeta "nixpkgs" "nixpkgs";
                  context = "home '${userHost}'";
                };
                pkgs = import nixpkgsInput {
                  inherit system;
                  config = nixpkgsConfig;
                  overlays = sharedOverlays;
                };
                # The lib purr exposes to home modules follows the home's own
                # nixpkgs. home-manager's own evaluation lib stays on the
                # caller-provided merged lib (matching home-manager's pinned
                # nixpkgs), so per-host replacement only surfaces via `purr.lib`.
                hostLib = perHostLib {
                  effectiveInputs = einputs;
                  meta = systemMeta;
                  inherit importedPurrLib namespace;
                  inherit lib;
                };
                hmEvalLib = homeLibFor hm lib;
                purrLib = homeLibFor hm hostLib;
                autoInjectModules = lib.optional autoInject {
                  home.username = mkDefault hostParsed.user;
                  home.homeDirectory = mkDefault (
                    if isDarwin then "/Users/${hostParsed.user}" else "/home/${hostParsed.user}"
                  );
                };
                purr = {
                  meta = {
                    inherit (hostParsed) user host;
                    inherit
                      arch
                      archFormat
                      format
                      isDarwin
                      system
                      ;
                    isLinux = !isDarwin;
                  };
                  inherit systemMeta;
                  systemMetas = registry;
                  # The merged namespace lib, uniformly available in both
                  # standalone and bridged homes (bridged homes can't get it
                  # as `lib` — see the TODO above).
                  lib = purrLib;
                };
              in
              hm.lib.homeManagerConfiguration {
                inherit pkgs;
                # home-manager defaults `lib` to `pkgs.lib`, which lacks the
                # `hm` extension its own modules expect (e.g. mako.nix uses
                # `lib.hm.deprecations.mkSettingsRenamedOptionModules`). Hand it
                # the merged lib with `hm` re-added.
                lib = hmEvalLib;
                modules =
                  autoInjectModules ++ extraModules.home or [ ] ++ [ discoveredHomes.${archFormat}.${userHost} ];
                extraSpecialArgs =
                  (purrArgs {
                    inherit
                      extraArgs
                      inputs
                      namespace
                      ;
                    lib = hmEvalLib;
                  })
                  // {
                    inherit
                      purr
                      system
                      ;
                    inherit (hostParsed) host user;
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
    buildSystemRegistry
    findMatchingHomes
    formatOutputKey
    imagesFromConfigs
    parseArchFormat
    parseUserHost
    ;
}
