{ fs, lib, ... }:
let
  inherit (lib)
    concatMap
    filterAttrs
    hasSuffix
    head
    recursiveUpdate
    removePrefix
    removeSuffix
    splitString
    tail
    ;

  inherit (fs)
    getDefaultNixFiles
    ;

  findModules =
    parentDir: type:
    let
      dir = parentDir + "/${type}";
      dirExists = builtins.pathExists dir;
    in
    if dirExists then
      let
        files = getDefaultNixFiles dir;
        fileList = builtins.map (file: {
          pathParts = splitString "/" (
            removePrefix (toString dir + "/") (removeSuffix "/default.nix" (toString file.path))
          );
          value = file.path;
        }) files;
        setNested =
          parts: val: if parts == [ ] then val else { ${head parts} = setNested (tail parts) val; };
      in
      builtins.foldl' (acc: item: recursiveUpdate acc (setNested item.pathParts item.value)) { } fileList
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
      collect = types: builtins.foldl' (acc: t: recursiveUpdate acc (findModules modulesDir t)) { } types;
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
in
{
  inherit
    collectModules
    discoverModules
    findModules
    findModulesFlat
    loadModules
    ;
}
