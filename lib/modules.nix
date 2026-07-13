{ fs, lib, ... }:
let
  inherit (lib)
    concatMap
    filterAttrs
    hasSuffix
    removePrefix
    removeSuffix
    splitString
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
      in
      builtins.listToAttrs (
        builtins.map (file: {
          name = removePrefix (toString dir + "/") (removeSuffix "/default.nix" (toString file.path));
          value = file.path;
        }) files
      )
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
      collect = types: builtins.foldl' (acc: t: acc // findModules modulesDir t) { } types;
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
      home = [
        "home"
        "shared"
      ];
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
in
{
  inherit
    discoverModules
    findAllModules
    findModules
    loadModules
    toKebabCase
    ;
}
