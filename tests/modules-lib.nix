# Tests for all functions in lib/modules.nix and lib/fs.nix
# Covers: getDefaultNixFiles, findModules, findModulesFlat, findModulesLib,
#         loadModules, discoverModules, discoverSystems, discoverHomes
{
  lib,
}:
let
  fs = import ../lib/fs.nix;
  modulesLib = import ../lib/modules.nix {
    inherit fs lib;
  };
  inherit (modulesLib)
    discoverHomes
    discoverModules
    discoverSystems
    findModules
    findModulesFlat
    findModulesLib
    loadModules
    ;
  inherit (fs)
    getDefaultNixFiles
    ;
  inherit (lib)
    attrNames
    elem
    hasSuffix
    length
    map
    removePrefix
    removeSuffix
    ;

  fixturesDir = ./fixtures;
  modulesFixtures = fixturesDir + "/modules";
  systemsFixtures = fixturesDir + "/systems";
  homesFixtures = fixturesDir + "/homes";
  libFixtures = fixturesDir + "/lib";

  relativePath = p: removePrefix (toString fixturesDir + "/") (toString p);
in
{
  getDefaultNixFiles = {
    tests = {
      "finds default.nix in immediate subdirs" = {
        expr = map (f: relativePath f.relPath) (getDefaultNixFiles libFixtures);
        expected = [
          "lib/helpers"
          "lib/utils"
        ];
      };

      "returns empty for nonexistent dir" = {
        expr = getDefaultNixFiles (fixturesDir + "/nonexistent");
        expected = [ ];
      };

      "each result has path and relPath" = {
        expr =
          let
            files = getDefaultNixFiles libFixtures;
            first = builtins.head files;
          in
          (builtins.isPath first.path) && (builtins.isString first.relPath or false);
        expected = true;
      };

      "recursively scans nested directories" = {
        expr =
          let
            files = getDefaultNixFiles modulesFixtures;
            relPaths = map (f: relativePath f.relPath) files;
            sorted = builtins.sort (a: b: a < b) relPaths;
          in
          sorted;
        expected = [
          "modules/home/desktop"
          "modules/nixos/common"
          "modules/nixos/my-service"
          "modules/shared/common"
        ];
      };
    };
  };

  findModulesFlat = {
    tests = {
      "returns flat map of immediate modules" = {
        expr =
          let
            result = findModulesFlat modulesFixtures "nixos";
          in
          builtins.attrNames result;
        expected = [
          "common"
          "my-service"
        ];
      };

      "returns {} for nonexistent dir" = {
        expr = findModulesFlat modulesFixtures "nonexistent";
        expected = { };
      };

      "values are paths ending with default.nix" = {
        expr =
          let
            result = findModulesFlat modulesFixtures "nixos";
            val = result."my-service";
          in
          hasSuffix "default.nix" (toString val);
        expected = true;
      };

      "each key maps to a path" = {
        expr =
          let
            result = findModulesFlat modulesFixtures "home";
          in
          builtins.attrNames result;
        expected = [ "desktop" ];
      };

      "skips subdirs without default.nix" = {
        expr = findModulesFlat modulesFixtures "shared";
        expected = {
          common = modulesFixtures + "/shared/common/default.nix";
        };
      };
    };
  };

  findModules = {
    tests = {
      "returns module tree with _module keys" = {
        expr =
          let
            result = findModules modulesFixtures "nixos";
            mod = result."my-service";
          in
          builtins.isAttrs mod && (mod ? _module);
        expected = true;
      };

      "returns {} for nonexistent dir" = {
        expr = findModules modulesFixtures "nonexistent";
        expected = { };
      };

      "discovers all submodules under a type" = {
        expr =
          let
            result = findModules modulesFixtures "nixos";
          in
          attrNames result;
        expected = [
          "common"
          "my-service"
        ];
      };

      "finds default.nix in the purr modules/user directory" = {
        expr =
          let
            result = findModules ../modules "user";
          in
          result ? _module;
        expected = true;
      };

      "_module value is the default.nix path" = {
        expr =
          let
            result = findModules modulesFixtures "nixos";
            mod = result."my-service";
          in
          hasSuffix "default.nix" (toString mod._module);
        expected = true;
      };

      "non-default.nix regular files are ignored" = {
        expr =
          let
            result = findModules modulesFixtures "home";
          in
          attrNames result;
        expected = [ "desktop" ];
      };
    };
  };

  findModulesLib = {
    tests = {
      "returns nested tree of lib files" = {
        expr =
          let
            result = findModulesLib libFixtures "";
            helpers = result.helpers or null;
          in
          helpers != null && builtins.isPath helpers;
        expected = true;
      };

      "returns {} for nonexistent dir" = {
        expr = findModulesLib (fixturesDir + "/nonexistent") "";
        expected = { };
      };

      "discovers all lib default.nix files" = {
        expr =
          let
            result = findModulesLib fixturesDir "lib";
          in
          builtins.attrNames result;
        expected = [
          "helpers"
          "utils"
        ];
      };

      "discovers purr's own lib directory" = {
        expr =
          let
            result = findModulesLib ./.. "lib";
            names = builtins.attrNames result;
          in
          builtins.elem "attrs" names && builtins.elem "systems" names;
        expected = true;
      };
    };
  };

  loadModules = {
    tests = {
      "recursively finds all .nix files" = {
        expr =
          let
            files = loadModules modulesFixtures;
          in
          length files;
        expected = 4;
      };

      "returns empty for nonexistent dir" = {
        expr = loadModules (fixturesDir + "/nonexistent");
        expected = [ ];
      };

      "all results are paths ending with .nix" = {
        expr =
          let
            files = loadModules modulesFixtures;
            allNix = builtins.all (f: hasSuffix ".nix" (toString f)) files;
          in
          allNix;
        expected = true;
      };
    };
  };

  discoverModules = {
    tests = {
      "discovers modules across multiple type directories" = {
        expr =
          let
            result = discoverModules modulesFixtures {
              nixos = [
                "nixos"
                "shared"
              ];
            };
          in
          builtins.attrNames result.nixos;
        expected = [
          "common"
          "my-service"
        ];
      };

      "merges overlapping modules from different dirs" = {
        expr =
          let
            result = discoverModules modulesFixtures {
              nixos = [
                "nixos"
                "shared"
              ];
            };
            common = result.nixos.common;
          in
          (builtins.isAttrs common)
          && (common ? _module)
          && (builtins.isAttrs common._module)
          && (common._module ? imports);
        expected = true;
      };

      "discovers home modules" = {
        expr =
          let
            result = discoverModules modulesFixtures { home = [ "home" ]; };
          in
          builtins.attrNames result.home;
        expected = [ "desktop" ];
      };

      "multiple module types in one call" = {
        expr =
          let
            result = discoverModules modulesFixtures {
              nixos = [ "nixos" ];
              home = [ "home" ];
            };
          in
          (builtins.attrNames result.nixos) ++ (builtins.attrNames result.home);
        expected = [
          "common"
          "my-service"
          "desktop"
        ];
      };

      "returns empty for missing type" = {
        expr =
          let
            result = discoverModules modulesFixtures {
              nixos = [ "nonexistent" ];
            };
          in
          result.nixos;
        expected = { };
      };

      "returns shallow empty for empty dirMap" = {
        expr = discoverModules modulesFixtures { };
        expected = { };
      };
    };
  };

  discoverSystems = {
    tests = {
      "discovers system configs by arch-format" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
          in
          builtins.attrNames result;
        expected = [
          "aarch64-darwin"
          "x86_64-linux"
        ];
      };

      "returns configs as nested attrset per system" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
            linux = result."x86_64-linux";
          in
          builtins.attrNames linux;
        expected = [ "myhost" ];
      };

      "system value is the default.nix path" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
          in
          hasSuffix "default.nix" (toString result."x86_64-linux".myhost);
        expected = true;
      };

      "discovers darwin configs" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
          in
          builtins.attrNames result."aarch64-darwin";
        expected = [ "macbook" ];
      };

      "returns {} for nonexistent dir" = {
        expr = discoverSystems (fixturesDir + "/nonexistent") "systems";
        expected = { };
      };
    };
  };

  discoverHomes = {
    tests = {
      "discovers home configs by arch and user@host" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
          in
          builtins.attrNames result;
        expected = [ "x86_64-linux" ];
      };

      "contains user@host keys" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
          in
          builtins.attrNames result."x86_64-linux";
        expected = [ "alice@myhost" ];
      };

      "home value is the default.nix path" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
          in
          hasSuffix "default.nix" (toString result."x86_64-linux"."alice@myhost");
        expected = true;
      };

      "returns {} for nonexistent dir" = {
        expr = discoverHomes (fixturesDir + "/nonexistent") "homes";
        expected = { };
      };
    };
  };
}
