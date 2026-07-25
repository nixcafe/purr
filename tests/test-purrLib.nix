# Tests for lib/purrLib.nix
{ lib }:
let
  inherit (lib) attrNames;

  attrs = import ../lib/attrs.nix;
  fs = import ../lib/fs.nix;
  mods = import ../lib/modules.nix {
    inherit fs lib;
  };
  nsm = import ../lib/namespacedModules.nix;
  libBuilder = import ../lib/purrLib.nix {
    inherit lib attrs;
    modules = mods;
    namespacedModules = nsm;
  };

  fixturesDir = ./fixtures;
in
{
  mergePurrLib = {
    tests = {
      "returns plain lib when null imported" = {
        expr = libBuilder.mergePurrLib lib null "ns";
        expected = lib;
      };
      "injects under namespace when set" = {
        expr =
          let
            result = libBuilder.mergePurrLib lib { greet = "hello"; } "demo";
          in
          result.demo.greet;
        expected = "hello";
      };
      "merges directly when no namespace" = {
        expr =
          let
            result = libBuilder.mergePurrLib lib { greet = "hello"; } null;
          in
          result.greet;
        expected = "hello";
      };
    };
  };

  buildImportedPurrLib = {
    tests = {
      "returns null when libDir is null" = {
        expr = libBuilder.buildImportedPurrLib {
          src = fixturesDir;
          libDir = null;
          namespace = "demo";
          inputs = { };
          flattenLib = false;
        };
        expected = null;
      };
      "builds nested lib from fixture dir" = {
        expr =
          let
            result = libBuilder.buildImportedPurrLib {
              src = fixturesDir;
              libDir = "lib";
              namespace = "demo";
              inputs = { };
              flattenLib = false;
            };
          in
          builtins.sort (a: b: a < b) (attrNames result);
        expected = [
          "default.nix"
          "helpers"
          "utils"
        ];
      };
      "flattenLib merges sub-modules into root" = {
        expr =
          let
            result = libBuilder.buildImportedPurrLib {
              src = fixturesDir;
              libDir = "lib";
              namespace = "demo";
              inputs = { };
              flattenLib = true;
            };
          in
          builtins.sort (a: b: a < b) (attrNames result);
        expected = [
          "helperUtil"
          "utilFunc"
        ];
      };
    };
  };
}
