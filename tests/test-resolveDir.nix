# Tests for lib/resolveDir.nix
{ lib }:
let
  resolver = import ../lib/resolveDir.nix {
    inherit lib;
  };

  fixturesDir = ./fixtures;
in
{
  resolveDir = {
    tests = {
      "returns dir when explicitly set" = {
        expr = resolver.resolveDir fixturesDir "explicit" [ "auto1" ];
        expected = "explicit";
      };
      "detects existing dir from candidates" = {
        expr = resolver.resolveDir fixturesDir null [
          "homes"
          "nonexistent"
        ];
        expected = "homes";
      };
      "returns first match from candidates" = {
        expr = resolver.resolveDir fixturesDir null [
          "systems"
          "homes"
        ];
        expected = "systems";
      };
      "returns null when no candidate exists" = {
        expr = resolver.resolveDir fixturesDir null [
          "nonexistent"
          "also-nope"
        ];
        expected = null;
      };
    };
  };

  resolveDirs = {
    tests = {
      "resolves known dirs from fixtures" = {
        expr =
          let
            result = resolver.resolveDirs fixturesDir {
              checksDir = null;
              shellsDir = null;
              overlaysDir = null;
              packagesDir = null;
              appsDir = null;
              templatesDir = null;
              formatterDir = null;
              legacyPackagesDir = null;
              systemsDir = null;
              homesDir = null;
              libDir = null;
            };
          in
          {
            systems = result.systemsDir;
            homes = result.homesDir;
            lib = result.libDir;
          };
        expected = {
          systems = "systems";
          homes = "homes";
          lib = "lib";
        };
      };
      "respects explicit dir overrides" = {
        expr =
          let
            result = resolver.resolveDirs fixturesDir {
              checksDir = null;
              shellsDir = null;
              overlaysDir = null;
              packagesDir = null;
              appsDir = null;
              templatesDir = null;
              formatterDir = null;
              legacyPackagesDir = null;
              systemsDir = "explicit-systems";
              homesDir = null;
              libDir = null;
            };
          in
          result.systemsDir;
        expected = "explicit-systems";
      };
    };
  };
}
