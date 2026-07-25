# Tests for lib/modules.nix — module discovery and collectModules
{ lib }:
let
  inherit (lib)
    attrNames
    elem
    hasSuffix
    length
    ;

  fs = import ../lib/fs.nix;
  mods = import ../lib/modules.nix {
    inherit fs lib;
  };

  inherit (mods)
    collectModules
    discoverHomes
    discoverModules
    discoverSystems
    findModules
    findModulesByName
    findModulesFlat
    findModulesLib
    loadModules
    validateByName
    ;

  fixturesDir = ./fixtures;
  modulesFixtures = fixturesDir + "/modules";
  systemsFixtures = fixturesDir + "/systems";
  homesFixtures = fixturesDir + "/homes";
  libFixtures = fixturesDir + "/lib";
in
{
  # ---- findModulesFlat ----
  findModulesFlat = {
    tests = {
      "returns flat map of immediate modules" = {
        expr =
          let
            result = findModulesFlat modulesFixtures "nixos";
          in
          attrNames result;
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
          in
          hasSuffix "default.nix" (toString result."my-service");
        expected = true;
      };
      "finds home modules" = {
        expr =
          let
            result = findModulesFlat modulesFixtures "home";
          in
          attrNames result;
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

  # ---- findModules ----
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
      "finds purr's own modules/user directory" = {
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

  # ---- findModulesLib ----
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
          attrNames result;
        expected = [
          "helpers"
          "utils"
        ];
      };
      "discovers purr's own lib directory" = {
        expr =
          let
            result = findModulesLib ./.. "lib";
            names = attrNames result;
          in
          elem "attrs" names && elem "systems" names;
        expected = true;
      };
    };
  };

  # ---- loadModules ----
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
          in
          builtins.all (f: hasSuffix ".nix" (toString f)) files;
        expected = true;
      };
    };
  };

  # ---- discoverModules ----
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
          attrNames result.nixos;
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
          attrNames result.home;
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
          (attrNames result.nixos) ++ (attrNames result.home);
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

  # ---- discoverSystems ----
  discoverSystems = {
    tests = {
      "discovers system configs by arch-format" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
          in
          attrNames result;
        expected = [
          "aarch64-darwin"
          "x86_64-linux"
        ];
      };
      "returns configs as nested attrset per system" = {
        expr =
          let
            result = discoverSystems fixturesDir "systems";
          in
          attrNames result."x86_64-linux";
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
          attrNames result."aarch64-darwin";
        expected = [ "macbook" ];
      };
      "returns {} for nonexistent dir" = {
        expr = discoverSystems (fixturesDir + "/nonexistent") "systems";
        expected = { };
      };
    };
  };

  # ---- discoverHomes ----
  discoverHomes = {
    tests = {
      "discovers home configs by arch and user@host" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
          in
          attrNames result;
        expected = [
          "aarch64-darwin"
          "x86_64-linux"
        ];
      };
      "contains user@host keys" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
          in
          attrNames result."x86_64-linux";
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
      "discovers darwin homes" = {
        expr =
          let
            result = discoverHomes fixturesDir "homes";
            darwin = result."aarch64-darwin" or null;
          in
          darwin != null && darwin ? "alice@macbook";
        expected = true;
      };
    };
  };

  # ---- collectModules ----
  collectModules = {
    tests = {
      "flattens a flat attrset of modules" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ];
          };
          b = {
            config.test = 1;
          };
        });
        expected = 2;
      };
      "flattens nested attrs" = {
        expr = builtins.length (collectModules {
          a.b = {
            imports = [ ];
          };
          a.c = {
            config.test = 1;
          };
        });
        expected = 2;
      };
      "handles empty attrs" = {
        expr = builtins.length (collectModules { });
        expected = 0;
      };
      "treats functions as leaf" = {
        expr = builtins.length (collectModules {
          a = x: x;
        });
        expected = 1;
      };
      "treats paths as leaf" = {
        expr = builtins.length (collectModules {
          a = ./default.nix;
        });
        expected = 1;
      };
      "treats attrsets with imports as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ./a.nix ];
          };
        });
        expected = 1;
      };
      "treats attrsets with options as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            options.services = { };
          };
        });
        expected = 1;
      };
      "treats attrsets with config as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            config.services = { };
          };
        });
        expected = 1;
      };
      "single module at root" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ];
          };
        });
        expected = 1;
      };
      "deeply nested 3+ levels" = {
        expr = builtins.length (collectModules {
          a.b.c = {
            imports = [ ];
          };
        });
        expected = 1;
      };
      "mixed types in same tree" = {
        expr = builtins.length (collectModules {
          a = x: x;
          b = ./default.nix;
          c.dir = {
            imports = [ ];
          };
        });
        expected = 3;
      };
      "empty nested attrset is skipped" = {
        expr = builtins.length (collectModules {
          a = { };
          b = {
            imports = [ ];
          };
        });
        expected = 1;
      };
    };
  };

  # ---- findModulesByName ----
  findModulesByName = {
    tests = {
      "discovers by-name package modules" = {
        expr =
          let
            result = findModulesByName fixturesDir "packages";
          in
          builtins.sort (a: b: a < b) (attrNames result);
        expected = [
          "badshard"
          "cowsay"
        ];
      };
      "module value is the package.nix path" = {
        expr =
          let
            result = findModulesByName fixturesDir "packages";
          in
          hasSuffix "package.nix" (toString result.cowsay);
        expected = true;
      };
      "returns {} when by-name dir doesn't exist" = {
        expr = findModulesByName fixturesDir "nonexistent";
        expected = { };
      };
      "returns {} when packages dir doesn't have by-name" = {
        expr = findModulesByName fixturesDir "modules";
        expected = { };
      };
    };
  };

  # ---- validateByName ----
  validateByName = {
    tests = {
      "returns empty list for valid by-name directory" = {
        expr = validateByName fixturesDir "modules";
        expected = [ ];
      };
      "returns shard mismatch error" = {
        expr =
          let
            errors = validateByName fixturesDir "packages";
            mismatch = builtins.filter (
              e: e.error != "" && builtins.match ".*shard mismatch.*" e.error != null
            ) errors;
          in
          builtins.length mismatch > 0;
        expected = true;
      };
      "returns missing package.nix error" = {
        expr =
          let
            errors = validateByName fixturesDir "packages";
            missing = builtins.filter (
              e: e.error != "" && builtins.match ".*missing package.nix.*" e.error != null
            ) errors;
          in
          builtins.length missing > 0;
        expected = true;
      };
      "returns empty when by-name dir does not exist" = {
        expr = validateByName fixturesDir "nonexistent";
        expected = [ ];
      };
    };
  };
}
