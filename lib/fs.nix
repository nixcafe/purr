{ lib, ... }:
let
  inherit (lib)
    filterAttrs
    removePrefix
    removeSuffix
    ;

  getDirectories =
    path:
    let
      entries = builtins.readDir path;
      dirNames = builtins.attrNames (filterAttrs (_: type: type == "directory") entries);
    in
    builtins.map (name: path + "/${name}") dirNames;

  readModules =
    path:
    let
      entries = builtins.readDir path;
      hasDefaultNix = builtins.hasAttr "default.nix" entries;
      subDirs = getDirectories path;
      current =
        if hasDefaultNix then
          [
            {
              name = baseNameOf path;
              path = path + "/default.nix";
            }
          ]
        else
          [ ];
    in
    current ++ builtins.concatMap readModules subDirs;

  getDefaultNixFiles =
    path:
    let
      scan =
        dir: acc:
        let
          entries = builtins.readDir dir;
          entryNames = builtins.attrNames entries;
          subDirNames = builtins.filter (n: entries.${n} == "directory") entryNames;
          hasDefault = builtins.elem "default.nix" entryNames;
          newAcc =
            if hasDefault then
              acc
              ++ [
                {
                  path = dir + "/default.nix";
                  relPath = dir;
                }
              ]
            else
              acc;
        in
        builtins.foldl' (a: d: scan (dir + "/${d}") a) newAcc subDirNames;
    in
    scan path [ ];

  pathToName =
    baseDir: filePath:
    let
      relativePath = removePrefix (toString baseDir + "/") (toString filePath);
      dirPart = builtins.dirOf relativePath;
    in
    removeSuffix "/default.nix" (dirPart + "/" + baseNameOf filePath);
in
{
  inherit
    getDefaultNixFiles
    getDirectories
    pathToName
    readModules
    ;
}
