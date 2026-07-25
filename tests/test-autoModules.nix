# Tests for lib/autoModules.nix
{ lib }:
let
  fs = import ../lib/fs.nix;
  mods = import ../lib/modules.nix {
    inherit fs lib;
  };
  autoMods = import ../lib/autoModules.nix {
    modules = mods;
  };

  fixturesDir = ./fixtures;
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
        expr = autoMods.templateModules fixturesDir null false lib null { };
        expected = { };
      };
    };
  };
}
