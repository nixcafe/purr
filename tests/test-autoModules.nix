# Tests for lib/autoModules.nix
{ lib }:
let
  inherit (lib) attrNames;

  fs = import ../lib/fs.nix;
  mods = import ../lib/modules.nix {
    inherit fs lib;
  };
  autoMods = import ../lib/autoModules.nix {
    modules = mods;
  };

  fixturesDir = ./fixtures;

  mockPkgs = {
    stdenv = "mock-stdenv";
    fetchurl = "mock-fetchurl";
    lib = "pkgs-lib";
    system = "x86_64-linux";
  };
in
{
  overlayModules = {
    tests = {
      "returns {} when overlaysDir is null" = {
        expr = autoMods.overlayModules fixturesDir null;
        expected = { };
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
          attrNames result;
        expected = [ "hello" ];
      };
      "discovers both regular and by-name when packagesByName is true" = {
        expr =
          let
            result = autoMods.autoModules fixturesDir mockPkgs lib null { } { } "packages" true;
          in
          builtins.sort (a: b: a < b) (attrNames result);
        expected = [
          "badshard"
          "cowsay"
          "hello"
          "lib-check"
          "spread-test"
        ];
      };
      "module receives pkgs attributes spread" = {
        expr =
          let
            pkgPkgs = mockPkgs // {
              testMarker = "found";
            };
            result = autoMods.autoModules fixturesDir pkgPkgs lib null { } { } "packages" false;
            modBody = result.hello;
          in
          modBody.type or null;
        expected = "regular";
      };
      "lib is overridden over pkgs.lib in module args" = {
        expr =
          let
            pkgWithLib = mockPkgs // {
              lib = "pkgs-lib";
            };
            result = autoMods.autoModules fixturesDir pkgWithLib "custom-lib" null { } { } "packages" false;
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
    };
  };
}
