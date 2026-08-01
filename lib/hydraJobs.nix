{
  lib,
  attrs,
  ...
}:
let
  inherit (lib)
    elem
    filterAttrs
    foldl'
    optional
    recursiveUpdate
    ;
  inherit (attrs) optionalAttrs;

  filterSystems =
    attrs': systems:
    if systems == null then attrs' else filterAttrs (system: _: elem system systems) attrs';

  mirrorOutputs =
    outputs: names: systems:
    let
      include =
        name:
        let
          sysFiltered = if outputs ? ${name} then filterSystems outputs.${name} systems else { };
        in
        optionalAttrs (sysFiltered != { }) { ${name} = sysFiltered; };
    in
    foldl' (acc: name: acc // include name) { } names;

  configOutputs =
    systemConfigs: homeConfigs: names: systems: homeSystems:
    let
      nixosConfigurations = systemConfigs.nixosConfigurations or { };
      darwinConfigurations = systemConfigs.darwinConfigurations or { };
      configSystems = systemConfigs.configSystems or { };
      nixosSystems = configSystems.nixosConfigurations or { };
      darwinSystems = configSystems.darwinConfigurations or { };
      homeSystems' = homeSystems;

      # The system per config is metadata known when the configs were built
      # (buildSystemConfigs.configSystems / the homeSystems map), so grouping is
      # a plain string lookup. Reading it from cfg.* would force nixpkgs/stdenv
      # evaluation just to obtain a string we already have.
      systemOf = systemsMap: name: systemsMap.${name};

      filterBySystem =
        attrs': systemsMap:
        if systems == null then
          attrs'
        else
          filterAttrs (name: _: elem (systemOf systemsMap name) systems) attrs';

      groupNixos =
        let
          filtered = filterBySystem nixosConfigurations nixosSystems;
        in
        optionalAttrs (filtered != { }) {
          nixosConfigs = foldl' (
            acc: name:
            let
              cfg = nixosConfigurations.${name};
              sys = systemOf nixosSystems name;
            in
            acc
            // {
              ${sys} = (acc.${sys} or { }) // {
                ${name} = cfg.config.system.build.toplevel;
              };
            }
          ) { } (builtins.attrNames filtered);
        };

      groupDarwin =
        let
          filtered = filterBySystem darwinConfigurations darwinSystems;
        in
        optionalAttrs (filtered != { }) {
          darwinConfigs = foldl' (
            acc: name:
            let
              cfg = darwinConfigurations.${name};
              sys = systemOf darwinSystems name;
            in
            acc
            // {
              ${sys} = (acc.${sys} or { }) // {
                ${name} = cfg.system;
              };
            }
          ) { } (builtins.attrNames filtered);
        };

      groupHome =
        let
          filtered = filterBySystem homeConfigs homeSystems';
        in
        optionalAttrs (filtered != { }) {
          homeConfigs = foldl' (
            acc: name:
            let
              cfg = homeConfigs.${name};
              sys = systemOf homeSystems' name;
            in
            acc
            // {
              ${sys} = (acc.${sys} or { }) // {
                ${name} = cfg.activationPackage;
              };
            }
          ) { } (builtins.attrNames filtered);
        };

      include =
        name:
        if name == "nixosConfigs" then
          groupNixos
        else if name == "darwinConfigs" then
          groupDarwin
        else if name == "homeConfigs" then
          groupHome
        else
          { };
    in
    foldl' (acc: name: acc // include name) { } names;

  hydraJobsFromDir =
    src: dir: systems: systemPkgs: lib': namespace: inputs: extraArgs:
    if dir != null && builtins.pathExists (src + "/${dir}") then
      let
        baseDir = src + "/${dir}";
        entries = builtins.readDir baseDir;
        groupNames = builtins.attrNames (filterAttrs (_: type: type == "directory") entries);

        filteredSystems =
          if systems == null then
            builtins.attrNames systemPkgs
          else
            builtins.filter (s: systemPkgs ? ${s}) systems;

        scanGroup =
          groupName:
          let
            groupPath = baseDir + "/${groupName}";
            groupEntries = builtins.readDir groupPath;
            jobNames = builtins.filter (
              n: groupEntries.${n} == "directory" && builtins.pathExists (groupPath + "/${n}/default.nix")
            ) (builtins.attrNames groupEntries);

            scanSystem =
              sys:
              let
                pkgs = systemPkgs.${sys};
              in
              foldl' (
                sysAcc: jobName:
                let
                  jobPath = groupPath + "/${jobName}/default.nix";
                  result = builtins.tryEval (
                    import jobPath (
                      extraArgs
                      // {
                        inherit
                          inputs
                          namespace
                          pkgs
                          ;
                        inherit (pkgs) system;
                        lib = lib';
                      }
                    )
                  );
                in
                if result.success && result.value != null then sysAcc // { ${jobName} = result.value; } else sysAcc
              ) { } jobNames;

            systemResults = foldl' (
              sysAcc: sys:
              let
                jobResults = scanSystem sys;
              in
              optionalAttrs (jobResults != { }) (sysAcc // { ${sys} = jobResults; })
            ) { } filteredSystems;
          in
          optionalAttrs (systemResults != { }) { ${groupName} = systemResults; };

        groupResults = foldl' (acc: g: acc // scanGroup g) { } groupNames;
      in
      groupResults
    else
      { };

  confs = import ./configs.nix { inherit lib; };

  inherit (confs) imagesFromConfigs;

  buildHydraJobs =
    {
      src,
      hydraJobsDir,
      hydraSystems,
      hydraJobsInclude,
      hydraJobsExtra,
      systemPkgs,
      perSystemOutputs,
      systemConfigs,
      homeConfigs ? { },
      homeSystems ? { },
      lib,
      namespace,
      inputs,
      extraArgs,
    }:
    let
      nixosConfigurations = systemConfigs.nixosConfigurations or { };
      darwinConfigurations = systemConfigs.darwinConfigurations or { };

      autoDetectNames =
        let
          perSystemNames = [
            "checks"
            "packages"
            "devShells"
            "legacyPackages"
            "formatter"
          ];
          fromPerSystem = builtins.filter (
            name: perSystemOutputs ? ${name} && perSystemOutputs.${name} != { }
          ) perSystemNames;
          fromNixos = optional (nixosConfigurations != { }) "nixosConfigs";
          fromDarwin = optional (darwinConfigurations != { }) "darwinConfigs";
          fromHome = optional (homeConfigs != { }) "homeConfigs";
        in
        fromPerSystem ++ fromNixos ++ fromDarwin ++ fromHome;

      effectiveInclude = if hydraJobsInclude == null then autoDetectNames else hydraJobsInclude;

      dirJobs = hydraJobsFromDir src hydraJobsDir hydraSystems systemPkgs lib namespace inputs extraArgs;
      mirrored = mirrorOutputs perSystemOutputs effectiveInclude hydraSystems;
      configMirrored = configOutputs systemConfigs homeConfigs effectiveInclude hydraSystems homeSystems;
      images = imagesFromConfigs (systemConfigs.imageRecipes or { }) hydraSystems;
    in
    foldl' recursiveUpdate { } [
      dirJobs
      mirrored
      configMirrored
      (optionalAttrs (images != { }) { inherit images; })
      hydraJobsExtra
    ];
in
{
  inherit
    buildHydraJobs
    configOutputs
    filterSystems
    hydraJobsFromDir
    mirrorOutputs
    ;
}
