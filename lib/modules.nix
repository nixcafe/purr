{ fs, lib, ... }:
let
  inherit (lib)
    concatMap
    filterAttrs
    hasSuffix
    head
    removePrefix
    removeSuffix
    splitString
    tail
    ;

  inherit (fs)
    getDefaultNixFiles
    ;

  readDirModules =
    dir:
    let
      entries = builtins.readDir dir;
      entryNames = builtins.attrNames entries;
      hasDefault = builtins.elem "default.nix" entryNames;

      subDirs = builtins.filter (n: builtins.elem entries.${n} [ "directory" ]) entryNames;
      subResults = builtins.listToAttrs (
        builtins.map (d: {
          name = d;
          value = readDirModules (dir + "/${d}");
        }) subDirs
      );
    in
    if hasDefault then
      subResults
      // {
        _module = dir + "/default.nix";
      }
    else
      subResults;

  mergeModuleTree =
    lhs: rhs:
    lhs
    // builtins.mapAttrs (
      k: vRhs:
      if k == "_module" && lhs ? "_module" then
        let
          extractPaths = v: if builtins.isPath v then [ v ] else v.imports or [ v ];
          paths = extractPaths lhs._module ++ extractPaths vRhs;
        in
        {
          imports = paths;
        }
      else if !(lhs ? ${k}) then
        vRhs
      else
        let
          vLhs = lhs.${k};
        in
        if builtins.isAttrs vLhs && builtins.isAttrs vRhs then
          mergeModuleTree vLhs vRhs
        else if !builtins.isAttrs vLhs && builtins.isAttrs vRhs then
          vRhs
          // {
            _module = {
              imports = [ vLhs ];
            };
          }
        else if builtins.isAttrs vLhs && !builtins.isAttrs vRhs then
          vLhs
          // {
            _module = {
              imports = [ vRhs ];
            };
          }
        else
          vRhs
    ) rhs;

  findModules =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then readDirModules dir else { };

  findModulesLib =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then
      let
        files = getDefaultNixFiles dir;
        setNested =
          parts: val: if parts == [ ] then val else { ${head parts} = setNested (tail parts) val; };
        entryFromFile =
          file:
          setNested (splitString "/" (
            removePrefix (toString dir + "/") (removeSuffix "/default.nix" (toString file.path))
          )) file.path;
      in
      builtins.foldl' (acc: item: acc // entryFromFile item) { } files
    else
      { };

  findModulesFlat =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then
      let
        entries = builtins.readDir dir;
        subDirs = builtins.attrNames (filterAttrs (_: t: t == "directory") entries);
        modules = builtins.filter (d: builtins.pathExists (dir + "/${d}/default.nix")) subDirs;
      in
      builtins.listToAttrs (
        builtins.map (d: {
          name = d;
          value = dir + "/${d}/default.nix";
        }) modules
      )
    else
      { };

  discoverModules =
    modulesDir: dirMap:
    let
      collect = types: builtins.foldl' (acc: t: mergeModuleTree acc (findModules modulesDir t)) { } types;
    in
    builtins.mapAttrs (_: collect) dirMap;

  loadModules =
    path:
    let
      entries = builtins.readDir path;
      nixFiles = builtins.attrNames (
        filterAttrs (name: type: type == "regular" && hasSuffix ".nix" name) entries
      );
      dirs = builtins.attrNames (filterAttrs (_name: type: type == "directory") entries);
      current = builtins.map (name: path + "/${name}") nixFiles;
      sub = concatMap (name: loadModules (path + "/${name}")) dirs;
    in
    current ++ sub;

  collectModules =
    attrs:
    let
      isModule = value: builtins.isAttrs value && (value ? imports || value ? options || value ? config);
      isLeaf =
        value:
        !builtins.isAttrs value || builtins.isFunction value || builtins.isPath value || isModule value;
    in
    concatMap (value: if isLeaf value then [ value ] else collectModules value) (
      builtins.attrValues attrs
    );

  discoverSystems =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then
      let
        entries = builtins.readDir dir;
        archDirs = builtins.attrNames (filterAttrs (_: t: t == "directory") entries);
        scanArch =
          archFormat:
          let
            archDir = dir + "/${archFormat}";
            archEntries = builtins.readDir archDir;
            subDirs = builtins.attrNames (filterAttrs (_: t: t == "directory") archEntries);
            systems = builtins.filter (d: builtins.pathExists (archDir + "/${d}/default.nix")) subDirs;
          in
          {
            name = archFormat;
            value = builtins.listToAttrs (
              builtins.map (d: {
                name = d;
                value = archDir + "/${d}/default.nix";
              }) systems
            );
          };
      in
      builtins.listToAttrs (builtins.map scanArch archDirs)
    else
      { };

  discoverHomes =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then
      let
        entries = builtins.readDir dir;
        archDirs = builtins.attrNames (filterAttrs (_: t: t == "directory") entries);
        scanArch =
          arch:
          let
            archDir = dir + "/${arch}";
            archEntries = builtins.readDir archDir;
            subDirs = builtins.attrNames (filterAttrs (_: t: t == "directory") archEntries);
            homes = builtins.filter (d: builtins.pathExists (archDir + "/${d}/default.nix")) subDirs;
          in
          {
            name = arch;
            value = builtins.listToAttrs (
              builtins.map (d: {
                name = d;
                value = archDir + "/${d}/default.nix";
              }) homes
            );
          };
      in
      builtins.listToAttrs (builtins.map scanArch archDirs)
    else
      { };
in
{
  inherit
    collectModules
    discoverHomes
    discoverModules
    discoverSystems
    findModules
    findModulesFlat
    findModulesLib
    loadModules
    mergeModuleTree
    readDirModules
    ;
}
