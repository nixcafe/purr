# Unit tests for lib/modules.nix — module discovery, merging, and collection.
{ lib }:
let
  inherit (lib)
    attrNames
    elem
    hasSuffix
    length
    sort
    ;

  fs = import ../../lib/fs.nix;
  mods = import ../../lib/modules.nix {
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
    mergeModuleTree
    readDirModules
    validateByName
    ;

  fixturesDir = ../fixtures;
  modulesFixtures = fixturesDir + "/modules";
  systemsFixtures = fixturesDir + "/systems";
  homesFixtures = fixturesDir + "/homes";
  libFixtures = fixturesDir + "/lib";
  packagesFixtures = fixturesDir + "/packages";
in
{
  # ---- readDirModules ----
  readDirModules = {
    tests = {
      "returns nested tree with _module path keys" = {
        expr =
          let
            result = readDirModules (modulesFixtures + "/nixos");
            mod = result."my-service";
          in
          builtins.isAttrs mod && hasSuffix "default.nix" (toString mod._module);
        expected = true;
      };
      "subdirectories become nested attrsets with _module" = {
        expr =
          let
            result = readDirModules (modulesFixtures + "/nixos");
            mod = result."my-service";
          in
          builtins.isAttrs mod && hasSuffix "default.nix" (toString mod._module);
        expected = true;
      };
      "dir without default.nix returns only subdirectories" = {
        expr =
          let
            result = readDirModules modulesFixtures;
          in
          (result ? _module) == false && (builtins.isAttrs result.home) && (result ? nixos);
        expected = true;
      };
    };
  };

  # ---- mergeModuleTree ----
  mergeModuleTree = {
    tests = {
      "merges _module paths into imports list" = {
        expr =
          let
            lhs = {
              common._module = /a/common/default.nix;
            };
            rhs = {
              common._module = /b/common/default.nix;
            };
            result = mergeModuleTree lhs rhs;
          in
          result.common._module.imports;
        expected = [
          /a/common/default.nix
          /b/common/default.nix
        ];
      };
      "deep merges nested attrsets" = {
        expr =
          let
            result =
              mergeModuleTree
                {
                  a.b.c = 1;
                }
                {
                  a.b.d = 2;
                };
          in
          result.a.b;
        expected = {
          c = 1;
          d = 2;
        };
      };
      "rhs value wins when both are leaves" = {
        expr =
          mergeModuleTree
            {
              a = 1;
            }
            {
              a = 2;
            };
        expected = {
          a = 2;
        };
      };
      "wraps rhs leaf under lhs attrs as an import" = {
        expr =
          let
            result =
              mergeModuleTree
                {
                  a = {
                    x = 1;
                  };
                }
                {
                  a = 2;
                };
          in
          result.a._module.imports;
        expected = [ 2 ];
      };
      "wraps lhs leaf under rhs attrs as an import" = {
        expr =
          let
            result =
              mergeModuleTree
                {
                  a = 1;
                }
                {
                  a = {
                    x = 2;
                  };
                };
          in
          result.a._module.imports;
        expected = [ 1 ];
      };
      "lhs-only and rhs-only keys are preserved" = {
        expr =
          let
            result =
              mergeModuleTree
                {
                  onlyLhs = 1;
                }
                {
                  onlyRhs = 2;
                };
          in
          attrNames result;
        expected = [
          "onlyLhs"
          "onlyRhs"
        ];
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
      "returns {} for a nonexistent type dir" = {
        expr = findModules modulesFixtures "nonexistent";
        expected = { };
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
      "discovers purr's own modules/user directory" = {
        expr =
          let
            result = findModules ../../modules "user";
          in
          result ? _module;
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

  # ---- findModulesFlat ----
  findModulesFlat = {
    tests = {
      "returns flat map of immediate modules" = {
        expr = attrNames (findModulesFlat modulesFixtures "nixos");
        expected = [
          "common"
          "my-service"
        ];
      };
      "values are paths ending with default.nix" = {
        expr = hasSuffix "default.nix" (toString (findModulesFlat modulesFixtures "nixos")."my-service");
        expected = true;
      };
      "finds home modules" = {
        expr = attrNames (findModulesFlat modulesFixtures "home");
        expected = [ "desktop" ];
      };
      "skips subdirs without default.nix" = {
        expr = findModulesFlat modulesFixtures "shared";
        expected = {
          common = modulesFixtures + "/shared/common/default.nix";
        };
      };
      "returns {} for nonexistent dir" = {
        expr = findModulesFlat modulesFixtures "nonexistent";
        expected = { };
      };
    };
  };

  # ---- findModulesLib ----
  findModulesLib = {
    tests = {
      "returns nested tree of lib file paths" = {
        expr =
          let
            result = findModulesLib libFixtures "";
          in
          result.helpers != null && builtins.isPath result.helpers;
        expected = true;
      };
      "excludes the root default.nix (imported separately)" = {
        expr = findModulesLib fixturesDir "lib" ? "";
        expected = false;
      };
      "discovers all lib submodule default.nix files" = {
        expr = attrNames (findModulesLib fixturesDir "lib");
        expected = [
          "helpers"
          "utils"
        ];
      };
      "returns {} for nonexistent dir" = {
        expr = findModulesLib (fixturesDir + "/nonexistent") "";
        expected = { };
      };
    };
  };

  # ---- findModulesByName ----
  findModulesByName = {
    tests = {
      "discovers by-name package modules" = {
        expr = sort (a: b: a < b) (attrNames (findModulesByName fixturesDir "packages"));
        expected = [
          "badshard"
          "cowsay"
        ];
      };
      "module value is the package.nix path" = {
        expr = hasSuffix "package.nix" (toString (findModulesByName fixturesDir "packages").cowsay);
        expected = true;
      };
      "returns {} when by-name dir doesn't exist" = {
        expr = findModulesByName fixturesDir "nonexistent";
        expected = { };
      };
      "returns {} when type dir has no by-name" = {
        expr = findModulesByName fixturesDir "modules";
        expected = { };
      };
    };
  };

  # ---- validateByName ----
  validateByName = {
    tests = {
      "returns empty list for a valid by-name directory" = {
        expr = validateByName fixturesDir "modules";
        expected = [ ];
      };
      "reports shard mismatch" = {
        expr =
          let
            errors = validateByName fixturesDir "packages";
            mismatches = builtins.filter (e: builtins.match ".*shard mismatch.*" e.error != null) errors;
          in
          builtins.length mismatches;
        expected = 1;
      };
      "reports missing package.nix" = {
        expr =
          let
            errors = validateByName fixturesDir "packages";
            missing = builtins.filter (e: builtins.match ".*missing package.nix.*" e.error != null) errors;
          in
          builtins.length missing;
        expected = 1;
      };
      "error records carry name and shard" = {
        expr =
          let
            errors = validateByName fixturesDir "packages";
            mismatch = builtins.head (
              builtins.filter (e: builtins.match ".*shard mismatch.*" e.error != null) errors
            );
          in
          {
            inherit (mismatch) name shard;
          };
        expected = {
          name = "badshard";
          shard = "xx";
        };
      };
      "returns empty when by-name dir does not exist" = {
        expr = validateByName fixturesDir "nonexistent";
        expected = [ ];
      };
    };
  };

  # ---- discoverModules ----
  discoverModules = {
    tests = {
      "discovers modules across multiple type directories" = {
        expr =
          attrNames
            (discoverModules modulesFixtures {
              nixos = [
                "nixos"
                "shared"
              ];
            }).nixos;
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
          builtins.isAttrs common
          && builtins.isAttrs common._module
          && builtins.isList common._module.imports;
        expected = true;
      };
      "merged module imports contain both default.nix paths" = {
        expr =
          let
            result = discoverModules modulesFixtures {
              nixos = [
                "nixos"
                "shared"
              ];
            };
            imports = result.nixos.common._module.imports;
          in
          builtins.all (p: hasSuffix "default.nix" (toString p)) imports && length imports == 2;
        expected = true;
      };
      "discovers home modules" = {
        expr =
          attrNames
            (discoverModules modulesFixtures {
              home = [ "home" ];
            }).home;
        expected = [ "desktop" ];
      };
      "multiple module types in one call" = {
        expr =
          (attrNames
            (discoverModules modulesFixtures {
              nixos = [ "nixos" ];
              home = [ "home" ];
            }).nixos
          )
          ++ (attrNames
            (discoverModules modulesFixtures {
              nixos = [ "nixos" ];
              home = [ "home" ];
            }).home
          );
        expected = [
          "common"
          "my-service"
          "desktop"
        ];
      };
      "returns empty for a missing type dir" = {
        expr =
          (discoverModules modulesFixtures {
            nixos = [ "nonexistent" ];
          }).nixos;
        expected = { };
      };
      "returns empty for an empty dirMap" = {
        expr = discoverModules modulesFixtures { };
        expected = { };
      };
    };
  };

  # ---- discoverSystems ----
  discoverSystems = {
    tests = {
      "discovers systems grouped by arch-format" = {
        expr = attrNames (discoverSystems fixturesDir "systems");
        expected = [
          "aarch64-darwin"
          "x86_64-linux"
        ];
      };
      "hosts listed per arch-format" = {
        expr = attrNames (discoverSystems fixturesDir "systems")."x86_64-linux";
        expected = [ "myhost" ];
      };
      "system value is the default.nix path" = {
        expr = hasSuffix "default.nix" (
          toString (discoverSystems fixturesDir "systems")."x86_64-linux".myhost
        );
        expected = true;
      };
      "discovers darwin configs" = {
        expr = attrNames (discoverSystems fixturesDir "systems")."aarch64-darwin";
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
      "discovers homes grouped by arch-format" = {
        expr = attrNames (discoverHomes fixturesDir "homes");
        expected = [
          "aarch64-darwin"
          "x86_64-linux"
        ];
      };
      "homes keyed by user@host" = {
        expr = attrNames (discoverHomes fixturesDir "homes")."x86_64-linux";
        expected = [ "alice@myhost" ];
      };
      "home value is the default.nix path" = {
        expr = hasSuffix "default.nix" (
          toString (discoverHomes fixturesDir "homes")."x86_64-linux"."alice@myhost"
        );
        expected = true;
      };
      "discovers darwin homes" = {
        expr = (discoverHomes fixturesDir "homes")."aarch64-darwin" ? "alice@macbook";
        expected = true;
      };
      "returns {} for nonexistent dir" = {
        expr = discoverHomes (fixturesDir + "/nonexistent") "homes";
        expected = { };
      };
    };
  };

  # ---- loadModules ----
  loadModules = {
    tests = {
      "recursively finds all .nix files" = {
        expr = length (loadModules modulesFixtures);
        expected = 4;
      };
      "all results are paths ending with .nix" = {
        expr = builtins.all (f: hasSuffix ".nix" (toString f)) (loadModules modulesFixtures);
        expected = true;
      };
      "finds files in deeply nested dirs" = {
        expr = length (loadModules (fixturesDir + "/packages/by-name"));
        expected = 2;
      };
    };
  };

  # ---- collectModules ----
  collectModules = {
    tests = {
      "flattens a flat attrset of modules" = {
        expr = length (collectModules {
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
        expr = length (collectModules {
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
        expr = length (collectModules { });
        expected = 0;
      };
      "treats functions as leaf" = {
        expr = length (collectModules {
          a = x: x;
        });
        expected = 1;
      };
      "treats paths as leaf" = {
        expr = length (collectModules {
          a = ./default.nix;
        });
        expected = 1;
      };
      "treats attrsets with imports as leaf" = {
        expr = length (collectModules {
          a = {
            imports = [ ./a.nix ];
          };
        });
        expected = 1;
      };
      "treats attrsets with options as leaf" = {
        expr = length (collectModules {
          a = {
            options.services = { };
          };
        });
        expected = 1;
      };
      "treats attrsets with config as leaf" = {
        expr = length (collectModules {
          a = {
            config.services = { };
          };
        });
        expected = 1;
      };
      "deeply nested 3+ levels" = {
        expr = length (collectModules {
          a.b.c = {
            imports = [ ];
          };
        });
        expected = 1;
      };
      "mixed types in the same tree" = {
        expr = length (collectModules {
          a = x: x;
          b = ./default.nix;
          c.dir = {
            imports = [ ];
          };
        });
        expected = 3;
      };
      "empty nested attrset is skipped" = {
        expr = length (collectModules {
          a = { };
          b = {
            imports = [ ];
          };
        });
        expected = 1;
      };
    };
  };
}
