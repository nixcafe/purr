# Unit tests for lib/fs.nix
{ lib }:
let
  inherit (lib) map removePrefix sort;

  fs = import ../../lib/fs.nix;

  fixturesDir = ../fixtures;
  libFixtures = fixturesDir + "/lib";
  modulesFixtures = fixturesDir + "/modules";

  relativePath = p: removePrefix (toString fixturesDir + "/") (toString p);

  relPaths = files: sort (a: b: a < b) (map (f: relativePath f.relPath) files);
in
{
  getDefaultNixFiles = {
    tests = {
      "finds the root default.nix plus immediate subdirs" = {
        expr = relPaths (fs.getDefaultNixFiles libFixtures);
        expected = [
          "lib"
          "lib/helpers"
          "lib/utils"
        ];
      };
      "recursively scans nested directories" = {
        expr = relPaths (fs.getDefaultNixFiles modulesFixtures);
        expected = [
          "modules/home/desktop"
          "modules/nixos/common"
          "modules/nixos/my-service"
          "modules/shared/common"
        ];
      };
      "each result exposes a path and relPath" = {
        expr =
          let
            files = fs.getDefaultNixFiles libFixtures;
          in
          builtins.all (f: builtins.isPath f.path && builtins.isPath f.relPath) files;
        expected = true;
      };
      "path points to a default.nix file" = {
        expr =
          let
            files = fs.getDefaultNixFiles libFixtures;
          in
          builtins.all (f: lib.hasSuffix "default.nix" (toString f.path)) files;
        expected = true;
      };
      "skips directories without default.nix" = {
        expr =
          let
            files = fs.getDefaultNixFiles (fixturesDir + "/systems");
          in
          relPaths files;
        expected = [
          "systems/aarch64-darwin/macbook"
          "systems/x86_64-linux/myhost"
        ];
      };
    };
  };
}
