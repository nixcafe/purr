# Unit tests for lib/autoModules.nix — per-system auto-discovery.
{ lib }:
let
  inherit (lib) attrNames sort;

  fs = import ../../lib/fs.nix;
  mods = import ../../lib/modules.nix {
    inherit fs lib;
  };
  autoMods = import ../../lib/autoModules.nix {
    modules = mods;
  };

  fixturesDir = ../fixtures;

  mockPkgs = {
    stdenv = "mock-stdenv";
    lib = "pkgs-lib";
    system = "x86_64-linux";
    hello = "hello-drv";
  };
in
{
  overlayModules = {
    tests = {
      "returns {} when overlaysDir is null" = {
        expr = autoMods.overlayModules fixturesDir null;
        expected = { };
      };
      "returns {} when overlaysDir does not exist" = {
        expr = autoMods.overlayModules fixturesDir "nonexistent";
        expected = { };
      };
      "discovers overlays as callable functions" = {
        expr =
          let
            result = autoMods.overlayModules fixturesDir "overlays";
          in
          builtins.isFunction result.custom;
        expected = true;
      };
      "applied overlay yields its attrset" = {
        expr =
          let
            result = autoMods.overlayModules fixturesDir "overlays";
            final = {
              hello = "final-hello";
            };
          in
          (result.custom final { }).custom;
        expected = "final-hello";
      };
    };
  };

  templateModules = {
    tests = {
      "returns {} when templatesDir is null" = {
        expr = autoMods.templateModules fixturesDir null false lib null { } { };
        expected = { };
      };
    };
  };

  autoFormatter = {
    tests = {
      "returns null when formatterDir is null" = {
        expr = autoMods.autoFormatter fixturesDir mockPkgs lib null { } { } null;
        expected = null;
      };
    };
  };

  autoModules = {
    tests = {
      "returns {} when dir is null" = {
        expr = autoMods.autoModules fixturesDir mockPkgs lib null { } { } null false;
        expected = { };
      };
      "discovers regular modules when packagesByName is false" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs lib null { } { } "packages" false;
          in
          sort (a: b: a < b) (attrNames result);
        expected = [
          "extra-test"
          "hello"
          "lib-check"
          "spread-test"
        ];
      };
      "discovers regular and by-name modules when packagesByName is true" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs lib null { } { } "packages" true;
          in
          sort (a: b: a < b) (attrNames result);
        expected = [
          "badshard"
          "cowsay"
          "extra-test"
          "hello"
          "lib-check"
          "spread-test"
        ];
      };
      "module receives pkgs attributes spread" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs lib null { } { } "packages" false;
          in
          result.hello.type;
        expected = "regular";
      };
      "module receives extraArgs" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs lib null { } {
              myCustom = "extra-value";
            } "packages" false;
          in
          result.extra-test.myCustom;
        expected = "extra-value";
      };
      "module lib override wins over pkgs.lib" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs "custom-lib" null { } { } "packages" false;
          in
          result.spread-test.libWorks;
        expected = true;
      };
      "module receives spread pkgs attrs like stdenv" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs "custom-lib" null { } { } "packages" false;
          in
          result.spread-test.foundStdenv;
        expected = true;
      };
    };
  };
}
