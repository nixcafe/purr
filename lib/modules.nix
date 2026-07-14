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

  toKebabCase =
    name:
    let
      parts = splitString "/" name;
      kebabParts = builtins.map (builtins.replaceStrings [ "_" ] [ "-" ]) parts;
    in
    builtins.concatStringsSep "/" kebabParts;

  discoverModules =
    modulesDir: dirMap:
    let
      collect = types: builtins.foldl' (acc: t: recursiveUpdate acc (findModules modulesDir t)) { } types;
    in
    builtins.mapAttrs (_: collect) dirMap;

  findAllModules =
    modulesDir:
    discoverModules modulesDir {
      nixos = [
        "nixos"
        "shared"
      ];
      darwin = [
        "darwin"
        "shared"
      ];
      home = [ "home" ];
    };

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
      isLeaf = value: !builtins.isAttrs value || builtins.isFunction value || builtins.isPath value;
    in
    concatMap (value: if isLeaf value then [ value ] else collectModules value) (
      builtins.attrValues attrs
    );
in
{
  inherit
    collectModules
    discoverModules
    findAllModules
    findModules
    loadModules
    toKebabCase
    ;
}
