# Tests for lib/fs.nix
{ lib }:
let
  fs = import ../lib/fs.nix;
  inherit (lib) map removePrefix;

  fixturesDir = ./fixtures;
  libFixtures = fixturesDir + "/lib";
  modulesFixtures = fixturesDir + "/modules";

  relativePath = p: removePrefix (toString fixturesDir + "/") (toString p);
in
{
  getDefaultNixFiles = {
    tests = {
      "finds default.nix in immediate subdirs" = {
        expr = map (f: relativePath f.relPath) (fs.getDefaultNixFiles libFixtures);
        expected = [
          "lib/helpers"
          "lib/utils"
        ];
      };
      "returns empty for nonexistent dir" = {
        expr = fs.getDefaultNixFiles (fixturesDir + "/nonexistent");
        expected = [ ];
      };
      "each result has path and relPath" = {
        expr =
          let
            files = fs.getDefaultNixFiles libFixtures;
            first = builtins.head files;
          in
          (builtins.isPath first.path) && (builtins.isString first.relPath or false);
        expected = true;
      };
      "recursively scans nested directories" = {
        expr =
          let
            files = fs.getDefaultNixFiles modulesFixtures;
            relPaths = map (f: relativePath f.relPath) files;
            sorted = builtins.sort (a: b: a < b) relPaths;
          in
          sorted;
        expected = [
          "modules/home/desktop"
          "modules/nixos/common"
          "modules/nixos/my-service"
          "modules/shared/common"
        ];
      };
    };
  };
}
