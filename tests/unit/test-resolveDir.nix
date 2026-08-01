# Unit tests for lib/resolveDir.nix — directory auto-detection.
{ lib }:
let
  resolver = import ../../lib/resolveDir.nix {
    inherit lib;
  };

  fixturesDir = ../fixtures;

  allNull = {
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
    hydraJobsDir = null;
  };
in
{
  resolveDir = {
    tests = {
      "returns the explicitly set dir" = {
        expr = resolver.resolveDir fixturesDir "explicit" [ "auto1" ];
        expected = "explicit";
      };
      "detects an existing dir from candidates" = {
        expr = resolver.resolveDir fixturesDir null [
          "homes"
          "nonexistent"
        ];
        expected = "homes";
      };
      "returns the first matching candidate" = {
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
            result = resolver.resolveDirs fixturesDir allNull;
          in
          {
            systems = result.systemsDir;
            homes = result.homesDir;
            lib = result.libDir;
            packages = result.packagesDir;
            hydraJobs = result.hydraJobsDir;
          };
        expected = {
          systems = "systems";
          homes = "homes";
          lib = "lib";
          packages = "packages";
          hydraJobs = "hydraJobs";
        };
      };
      "resolves null for dirs not present in fixtures" = {
        expr =
          let
            result = resolver.resolveDirs fixturesDir allNull;
          in
          {
            checks = result.checksDir;
            shells = result.shellsDir;
            apps = result.appsDir;
            templates = result.templatesDir;
            formatter = result.formatterDir;
            legacyPackages = result.legacyPackagesDir;
          };
        expected = {
          checks = null;
          shells = null;
          apps = null;
          templates = null;
          formatter = null;
          legacyPackages = null;
        };
      };
      "respects explicit dir overrides" = {
        expr =
          let
            result = resolver.resolveDirs fixturesDir (
              allNull
              // {
                systemsDir = "explicit-systems";
              }
            );
          in
          result.systemsDir;
        expected = "explicit-systems";
      };
      "shells falls back to devShells candidate" = {
        expr =
          let
            result = resolver.resolveDir (fixturesDir + "/modules") null [
              "shells"
              "devShells"
            ];
          in
          result;
        expected = null;
      };
    };
  };
}
