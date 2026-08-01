# Unit tests for lib/purrLib.nix — lib construction and merging.
{ lib }:
let
  inherit (lib) attrNames sort;

  attrs = import ../../lib/attrs.nix;
  fs = import ../../lib/fs.nix;
  mods = import ../../lib/modules.nix {
    inherit fs lib;
  };
  nsm = import ../../lib/namespacedModules.nix;
  libBuilder = import ../../lib/purrLib.nix {
    inherit lib attrs;
    modules = mods;
    namespacedModules = nsm;
  };

  fixturesDir = ../fixtures;
in
{
  mergePurrLib = {
    tests = {
      "returns plain lib when imported lib is null" = {
        expr =
          let
            result = libBuilder.mergePurrLib lib null "ns";
          in
          {
            hasNamespace = result ? "ns";
            libComplete = (result ? attrNames) && (result ? lists);
          };
        expected = {
          hasNamespace = false;
          libComplete = true;
        };
      };
      "injects imported lib under namespace when set" = {
        expr =
          let
            result = libBuilder.mergePurrLib lib {
              greet = "hello";
            } "demo";
          in
          {
            hasNamespace = result ? "demo";
            greet = result.demo.greet;
            standardLibPreserved = result ? attrNames;
          };
        expected = {
          hasNamespace = true;
          greet = "hello";
          standardLibPreserved = true;
        };
      };
      "merges directly when no namespace" = {
        expr =
          let
            result = libBuilder.mergePurrLib lib {
              greet = "hello";
            } null;
          in
          {
            inherit (result) greet;
            standardLibPreserved = result ? attrNames;
          };
        expected = {
          greet = "hello";
          standardLibPreserved = true;
        };
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
          {
            keys = sort (a: b: a < b) (attrNames result);
            helper = result.helpers.helperUtil;
            util = result.utils.utilFunc;
          };
        expected = {
          keys = [
            "helpers"
            "utils"
          ];
          helper = "helper";
          util = "util";
        };
      };
      "flattenLib merges sub-module leaves into root" = {
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
          {
            helper = result.helperUtil;
            util = result.utilFunc;
            noNested = !(result ? helpers) && !(result ? utils);
          };
        expected = {
          helper = "helper";
          util = "util";
          noNested = true;
        };
      };
      "root default.nix is merged in" = {
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
          builtins.isAttrs result;
        expected = true;
      };
      "plain attrset lib modules are not called as functions" = {
        expr =
          let
            result = libBuilder.buildImportedPurrLib {
              src = fixturesDir;
              libDir = "plain-lib";
              namespace = "demo";
              inputs = { };
              flattenLib = true;
            };
          in
          {
            root = result.rootKey;
            data = result.theme;
            fn = result.helper;
          };
        expected = {
          root = "root";
          data = "dark";
          fn = "works";
        };
      };
      "plain attrset lib modules keep nested layout when flattenLib is false" = {
        expr =
          let
            result = libBuilder.buildImportedPurrLib {
              src = fixturesDir;
              libDir = "plain-lib";
              namespace = "demo";
              inputs = { };
              flattenLib = false;
            };
          in
          {
            root = result.rootKey;
            data = result.data.theme;
            fn = result.fn.helper;
          };
        expected = {
          root = "root";
          data = "dark";
          fn = "works";
        };
      };
    };
  };
}
