# Tests for lib/systems.nix
{ lib }:
let
  systems = import ../lib/systems.nix;
in
{
  eachSystem = {
    tests = {
      "maps single system" = {
        expr = systems.eachSystem [ "x86_64-linux" ] (s: "system-${s}");
        expected = {
          x86_64-linux = "system-x86_64-linux";
        };
      };
      "handles empty list" = {
        expr = systems.eachSystem [ ] lib.id;
        expected = { };
      };
      "maps multiple systems" = {
        expr = builtins.attrNames (
          systems.eachSystem [
            "x86_64-linux"
            "aarch64-linux"
          ] lib.id
        );
        expected = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      };
    };
  };

  defaultSystems = {
    tests = {
      "is correct" = {
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
      "iterates defaults" = {
        expr = builtins.attrNames (systems.eachDefaultSystem (_: "ok"));
        expected = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];
      };
    };
  };
}
