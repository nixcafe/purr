{
  src,
}:

let
  lockFile = builtins.fromJSON (builtins.readFile (src + "/flake.lock"));

  fetchTree =
    info:
    if info.type == "github" then
      {
        outPath = builtins.fetchTarball {
          url = "https://api.${info.host or "github.com"}/repos/${info.owner}/${info.repo}/tarball/${info.rev}";
          sha256 = info.narHash;
        };
        inherit (info) rev narHash lastModified;
        shortRev = builtins.substring 0 7 info.rev;
      }
    else if info.type == "git" then
      {
        outPath = builtins.fetchGit (
          {
            inherit (info) url;
          }
          // (if info ? rev then { inherit (info) rev; } else { })
          // (if info ? ref then { inherit (info) ref; } else { })
        );
        inherit (info) rev narHash lastModified;
      }
      // (if info ? rev then { shortRev = builtins.substring 0 7 info.rev; } else { })
    else if info.type == "tarball" then
      {
        outPath = builtins.fetchTarball {
          inherit (info) url;
          sha256 = info.narHash;
        };
      }
    else if info.type == "path" then
      {
        outPath = builtins.path {
          inherit (info) path;
          name = "source";
        };
      }
    else
      throw "flake-compat: unsupported input type '${info.type}'";

  allNodes = builtins.mapAttrs (
    key: node:

    let
      parentKey =
        if key == lockFile.root then key else resolveInput lockFile.root (node.parent or lockFile.root);

      parent = allNodes.${parentKey};

      isRelative =
        node.locked.type or null == "path" && builtins.substring 0 1 (node.locked.path or "") != "/";

      sourceInfo =
        if key == lockFile.root then
          {
            outPath = builtins.path {
              path = src;
              name = "source";
            };
          }
        else if isRelative then
          parent.sourceInfo
        else
          fetchTree (node.info or { } // builtins.removeAttrs node.locked [ "dir" ]);

      subdir = node.locked.dir or "";

      outPath =
        if isRelative then
          parent.outPath + (if node.locked.path or "" == "" then "" else "/" + node.locked.path)
        else
          sourceInfo.outPath + (if subdir == "" then "" else "/" + subdir);

      flake = import (outPath + "/flake.nix");

      inputs = builtins.mapAttrs (_inputName: inputSpec: allNodes.${resolveInput inputSpec}.result) (
        node.inputs or { }
      );

      resolveInput =
        inputSpec: if builtins.isList inputSpec then followPath lockFile.root inputSpec else inputSpec;

      followPath =
        nodeName: path:
        if path == [ ] then
          nodeName
        else
          followPath (resolveInput lockFile.nodes.${nodeName}.inputs.${builtins.head path}) (
            builtins.tail path
          );

      outputs = flake.outputs (inputs // { self = result; });

      result =
        outputs
        // sourceInfo
        // {
          inherit
            outPath
            inputs
            outputs
            sourceInfo
            ;
          _type = "flake";
        };
    in
    {
      inherit outPath sourceInfo;
      result =
        if node.flake or true then
          assert builtins.isFunction flake.outputs;
          result
        else
          sourceInfo // { inherit sourceInfo outPath; };
    }
  ) lockFile.nodes;
in
{
  outputs = allNodes.${lockFile.root}.result;
}
