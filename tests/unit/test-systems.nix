# Unit tests for lib/systems.nix
{ lib }:
let
  systems = import ../../lib/systems.nix;
in
{
  eachSystem = {
    tests = {
      "maps a single system" = {
        expr = systems.eachSystem [ "x86_64-linux" ] (s: "system-${s}");
        expected = {
          x86_64-linux = "system-x86_64-linux";
        };
      };
      "maps multiple systems" = {
        expr = systems.eachSystem [
          "x86_64-linux"
          "aarch64-linux"
        ] (s: s);
        expected = {
          x86_64-linux = "x86_64-linux";
          aarch64-linux = "aarch64-linux";
        };
      };
      "handles empty list" = {
        expr = systems.eachSystem [ ] (s: s);
        expected = { };
      };
      "maps to the correct value per system" = {
        expr = systems.eachSystem [
          "x86_64-linux"
          "aarch64-darwin"
          "aarch64-linux"
        ] (s: "got:${s}");
        expected = {
          x86_64-linux = "got:x86_64-linux";
          aarch64-darwin = "got:aarch64-darwin";
          aarch64-linux = "got:aarch64-linux";
        };
      };
      "function receives the system name" = {
        expr = systems.eachSystem [ "aarch64-darwin" ] (s: "got:${s}");
        expected = {
          aarch64-darwin = "got:aarch64-darwin";
        };
      };
    };
  };

  defaultSystems = {
    tests = {
      "defaultSystems has the three supported systems" = {
        expr = systems.defaultSystems;
        expected = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];
      };
    };
  };

  eachDefaultSystem = {
    tests = {
      "iterates over default systems" = {
        expr = systems.eachDefaultSystem (_: "ok");
        expected = {
          x86_64-linux = "ok";
          aarch64-linux = "ok";
          aarch64-darwin = "ok";
        };
      };
      "eachDefaultSystem is eachSystem applied to defaultSystems" = {
        expr = systems.eachDefaultSystem lib.id;
        expected = systems.eachSystem systems.defaultSystems lib.id;
      };
    };
  };
}
