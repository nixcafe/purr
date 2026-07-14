let
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
in
{
  inherit getDefaultNixFiles;
}
