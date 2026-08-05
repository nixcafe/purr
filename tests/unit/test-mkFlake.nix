# Unit tests for lib/mkFlake.nix.
#
# Uses the same input wiring as the integration harness but with simple
# inspectable mocks (functions returning their args) instead of the real
# evalModules, so option-level behaviors are checked cheaply.
{ lib }:
let
  attrsMod = import ../../lib/attrs.nix;
  systemsMod = import ../../lib/systems.nix;
  fs = import ../../lib/fs.nix;

  mods = import ../../lib/modules.nix {
    inherit fs lib;
  };

  confs = import ../../lib/configs.nix {
    inherit lib;
  };

  nsm = import ../../lib/namespacedModules.nix;

  resolver = import ../../lib/resolveDir.nix {
    inherit lib;
  };

  libBuilder = import ../../lib/purrLib.nix {
    inherit lib;
    attrs = attrsMod;
    modules = mods;
    namespacedModules = nsm;
  };

  autoMods = import ../../lib/autoModules.nix {
    modules = mods;
  };

  mkFlakeLib = import ../../lib/mkFlake.nix {
    inherit
      lib
      autoMods
      ;
    attrs = attrsMod;
    confs = confs;
    mods = mods;
    nsm = nsm;
    purrLib = libBuilder;
    resolveDir = resolver;
    systems = systemsMod;
  };

  inherit (mkFlakeLib) mkFlake;

  fixturesDir = ../fixtures;

  nixosSystem = args: args;

  homeManagerConfiguration = args: args;

  darwinSystem = args: args;

  nixpkgsInput = {
    outPath = ../integration/mocks/nixpkgs;
    __toString = self: self.outPath;
    lib = lib // {
      inherit nixosSystem;
    };
  };

  homeManagerInput = {
    lib = {
      inherit homeManagerConfiguration;
    };
    nixosModules.home-manager = {
      _file = "mock-home-manager";
    };
    darwinModules.home-manager = {
      _file = "mock-home-manager-darwin";
    };
  };

  nixDarwinInput = {
    lib = {
      inherit darwinSystem;
    };
  };

  inputsBase = {
    nixpkgs = nixpkgsInput;
  };

  inputsWithHome = {
    nixpkgs = nixpkgsInput;
    home-manager = homeManagerInput;
  };

  inputsAll = {
    nixpkgs = nixpkgsInput;
    home-manager = homeManagerInput;
    nix-darwin = nixDarwinInput;
  };
in
{
  # ---- systems discovery ----
  systemsOnly = {
    tests = {
      "discovers myhost into nixosConfigurations" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              systemsDir = "systems";
              autoInject = false;
            };
          in
          builtins.attrNames (result.nixosConfigurations or { });
        expected = [ "myhost" ];
      };
      "system config carries modules and specialArgs" = {
        expr =
          let
            cfg =
              (mkFlake {
                inputs = inputsBase;
                src = fixturesDir;
                systemsDir = "systems";
                autoInject = false;
              }).nixosConfigurations.myhost;
          in
          {
            hasModules = cfg ? modules;
            hasSpecialArgs = cfg ? specialArgs;
            inherit (cfg) system;
          };
        expected = {
          hasModules = true;
          hasSpecialArgs = true;
          system = "x86_64-linux";
        };
      };
      "specialArgs carries purr metadata" = {
        expr =
          let
            special =
              (mkFlake {
                inputs = inputsBase;
                src = fixturesDir;
                systemsDir = "systems";
                autoInject = false;
              }).nixosConfigurations.myhost.specialArgs;
          in
          {
            inherit (special) host;
            namespace = special.namespace or null;
            purrName = special.purr.meta.name;
            archFormat = special.purr.meta.archFormat;
          };
        expected = {
          host = "myhost";
          namespace = null;
          purrName = "myhost";
          archFormat = "x86_64-linux";
        };
      };
      "nonexistent systemsDir produces no nixosConfigurations key" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              systemsDir = "nonexistent";
              autoInject = false;
            };
          in
          result ? nixosConfigurations;
        expected = false;
      };
    };
  };

  # ---- homes discovery ----
  homesOnly = {
    tests = {
      "discovers homes into homeConfigurations" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsWithHome;
              src = fixturesDir;
              homesDir = "homes";
              autoInject = false;
            };
          in
          builtins.attrNames (result.homeConfigurations or { });
        expected = [
          "alice@macbook"
          "alice@myhost"
        ];
      };
      "home config carries modules and extraSpecialArgs" = {
        expr =
          let
            cfg =
              (mkFlake {
                inputs = inputsWithHome;
                src = fixturesDir;
                homesDir = "homes";
                autoInject = false;
              }).homeConfigurations."alice@myhost";
          in
          {
            hasModules = cfg ? modules;
            pkgsSystem = cfg.pkgs.system;
            user = cfg.extraSpecialArgs.purr.meta.user;
            host = cfg.extraSpecialArgs.purr.meta.host;
          };
        expected = {
          hasModules = true;
          pkgsSystem = "x86_64-linux";
          user = "alice";
          host = "myhost";
        };
      };
      "no home-manager input yields empty homeConfigurations" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              homesDir = "homes";
              autoInject = false;
            };
          in
          result.homeConfigurations or { };
        expected = { };
      };
    };
  };

  # ---- systems + homes integration ----
  systemsAndHomes = {
    tests = {
      "purr.homes metadata lists linked homes" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsWithHome;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
          in
          (result.nixosConfigurations.myhost.specialArgs.purr or { }).meta.homes;
        expected = [
          {
            user = "alice";
            host = "myhost";
          }
        ];
      };
      "home-manager bridge module wires linked users into system modules" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsWithHome;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
            bridges = builtins.filter lib.isFunction result.nixosConfigurations.myhost.modules;
            applied = builtins.map (
              f:
              f {
                config = { };
                lib = lib;
              }
            ) bridges;
            bridge = builtins.head applied;
          in
          {
            users = builtins.attrNames (bridge."home-manager".users or { });
            importsHome = builtins.any (
              m: builtins.isPath m && lib.hasSuffix "alice@myhost/default.nix" (toString m)
            ) (bridge."home-manager".users.alice.imports or [ ]);
          };
        expected = {
          users = [ "alice" ];
          importsHome = true;
        };
      };
      "linked homes are also built standalone" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsWithHome;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
          in
          result.homeConfigurations ? "alice@myhost";
        expected = true;
      };
    };
  };

  # ---- full pipeline ----
  fullPipeline = {
    tests = {
      "exposes lib, systems, homes, and module outputs" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsAll;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              modulesDir = "modules";
              systemsDir = "systems";
              homesDir = "homes";
              bundleModules = true;
              autoInject = false;
            };
          in
          {
            lib = result ? lib;
            nixosConfigurations = result ? nixosConfigurations;
            homeConfigurations = result ? homeConfigurations;
            nixosModules = result ? nixosModules;
            darwinModules = result ? darwinModules;
            homeModules = result ? homeModules;
          };
        expected = {
          lib = true;
          nixosConfigurations = true;
          homeConfigurations = true;
          nixosModules = true;
          darwinModules = true;
          homeModules = true;
        };
      };
      "namespace lib accessible via result.lib.demo" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsAll;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              modulesDir = "modules";
              systemsDir = "systems";
              homesDir = "homes";
              bundleModules = true;
              autoInject = false;
            };
          in
          {
            helper = result.lib.demo.helpers.helperUtil or null;
            util = result.lib.demo.utils.utilFunc or null;
          };
        expected = {
          helper = "helper";
          util = "util";
        };
      };
      "system specialArgs carries namespaced lib" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsAll;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              modulesDir = "modules";
              systemsDir = "systems";
              homesDir = "homes";
              bundleModules = true;
              autoInject = false;
            };
          in
          (result.nixosConfigurations.myhost.specialArgs.lib or { }) ? "demo";
        expected = true;
      };
      "home extraSpecialArgs carries merged lib" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsAll;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              modulesDir = "modules";
              systemsDir = "systems";
              homesDir = "homes";
              bundleModules = true;
              autoInject = false;
            };
          in
          (result.homeConfigurations."alice@myhost".extraSpecialArgs.lib or { }) ? "demo";
        expected = true;
      };
    };
  };

  # ---- lib flattening ----
  flattenLib = {
    tests = {
      "flattenLib false keeps nested lib module groups" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              flattenLib = false;
              autoInject = false;
            };
          in
          {
            helper = result.lib.demo.helpers.helperUtil or null;
            util = result.lib.demo.utils.utilFunc or null;
          };
        expected = {
          helper = "helper";
          util = "util";
        };
      };
      "flattenLib true merges leaf functions into lib root" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              flattenLib = true;
              autoInject = false;
            };
          in
          {
            helper = result.lib.demo.helperUtil or null;
            util = result.lib.demo.utilFunc or null;
            nestedGone = result.lib.demo ? helpers;
          };
        expected = {
          helper = "helper";
          util = "util";
          nestedGone = false;
        };
      };
    };
  };

  # ---- module bundling ----
  bundleModules = {
    tests = {
      "bundleModules true adds a default module importing authored modules" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              modulesDir = "modules";
              bundleModules = true;
              autoInject = false;
            };
            dflt = result.nixosModules.default or { };
          in
          {
            hasDefault = result.nixosModules ? "default";
            importCount = builtins.length (dflt.imports or [ ]);
            keepsAuthored = (result.nixosModules ? "common") && (result.nixosModules ? "my-service");
          };
        expected = {
          hasDefault = true;
          importCount = 2;
          keepsAuthored = true;
        };
      };
      "bundleExtraModules false excludes extra modules from the bundle" = {
        expr =
          let
            extraMod = {
              config.services.extra = true;
            };
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              modulesDir = "modules";
              bundleModules = true;
              bundleExtraModules = false;
              extraModules.nixos = [ extraMod ];
              autoInject = false;
            };
          in
          builtins.elem extraMod (result.nixosModules.default.imports or [ ]);
        expected = false;
      };
      "bundleExtraModules true includes extra modules in the bundle" = {
        expr =
          let
            extraMod = {
              config.services.extra = true;
            };
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              modulesDir = "modules";
              bundleModules = true;
              bundleExtraModules = true;
              extraModules.nixos = [ extraMod ];
              autoInject = false;
            };
          in
          builtins.elem extraMod (result.nixosModules.default.imports or [ ]);
        expected = true;
      };
      "bundleModules false keeps extra modules out of default imports" = {
        expr =
          let
            extraMod = {
              config.services.extra = true;
            };
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              modulesDir = "modules";
              bundleModules = false;
              bundleExtraModules = true;
              extraModules.nixos = [ extraMod ];
              autoInject = false;
            };
          in
          builtins.elem extraMod (result.nixosModules.default.imports or [ ]);
        expected = false;
      };
    };
  };

  # ---- custom module types ----
  customModuleTypes = {
    tests = {
      "moduleTypes nixos list controls which module subdirs are discovered" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              modulesDir = "modules";
              moduleTypes = {
                nixos = [ "home" ];
              };
              autoInject = false;
            };
          in
          {
            hasDesktop = result.nixosModules ? "desktop";
            hasCommon = result.nixosModules ? "common";
          };
        expected = {
          hasDesktop = true;
          hasCommon = false;
        };
      };
    };
  };

  # ---- custom systems ----
  customSystems = {
    tests = {
      "only the listed systems appear in per-system outputs" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              systems = [ "x86_64-linux" ];
              autoInject = false;
            };
          in
          builtins.attrNames (result.packages or { });
        expected = [ "x86_64-linux" ];
      };
    };
  };

  # ---- outputsBuilder ----
  outputsBuilder = {
    tests = {
      "custom output produced per system and pivoted" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              autoInject = false;
              outputsBuilder =
                { system, ... }:
                {
                  specialOutput = "hello-${system}";
                };
            };
          in
          {
            systems = builtins.attrNames (result.specialOutput or { });
            x86 = result.specialOutput."x86_64-linux" or null;
          };
        expected = {
          systems = [
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ];
          x86 = "hello-x86_64-linux";
        };
      };
    };
  };

  # ---- by-name packages ----
  packagesByName = {
    tests = {
      "packagesByName false discovers regular packages only" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              packagesByName = false;
              autoInject = false;
            };
            pkgs = result.packages."x86_64-linux" or { };
          in
          {
            hasHello = pkgs ? "hello";
            hasCowsay = pkgs ? "cowsay";
          };
        expected = {
          hasHello = true;
          hasCowsay = false;
        };
      };
      "packagesByName true also discovers by-name packages" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              packagesByName = true;
              autoInject = false;
            };
            pkgs = result.packages."x86_64-linux" or { };
          in
          {
            hasHello = pkgs ? "hello";
            hasCowsay = pkgs ? "cowsay";
          };
        expected = {
          hasHello = true;
          hasCowsay = true;
        };
      };
    };
  };

  # ---- extraArgs ----
  extraArgs = {
    tests = {
      "extraArgs flows to outputsBuilder" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              autoInject = false;
              extraArgs = {
                myConstructor = "builder-value";
              };
              outputsBuilder =
                { myConstructor, ... }:
                {
                  gotConstructor = myConstructor;
                };
            };
          in
          result.gotConstructor."x86_64-linux" or null;
        expected = "builder-value";
      };
      "extraArgs flows to system specialArgs" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              systemsDir = "systems";
              autoInject = false;
              extraArgs = {
                myCustom = "system-value";
              };
            };
          in
          result.nixosConfigurations.myhost.specialArgs.myCustom or null;
        expected = "system-value";
      };
      "extraArgs flows to home extraSpecialArgs" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsWithHome;
              src = fixturesDir;
              homesDir = "homes";
              autoInject = false;
              extraArgs = {
                myHomeCustom = "home-value";
              };
            };
          in
          result.homeConfigurations."alice@myhost".extraSpecialArgs.myHomeCustom or null;
        expected = "home-value";
      };
      "extraArgs flows to packages" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              autoInject = false;
              extraArgs = {
                myCustom = "pkg-value";
              };
            };
          in
          (result.packages."x86_64-linux".extra-test or { }).myCustom or null;
        expected = "pkg-value";
      };
      "extraArgs does not override purr keys" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = "my-ns";
              autoInject = false;
              extraArgs = {
                namespace = "evil-ns";
              };
            };
          in
          result.nixosConfigurations.myhost.specialArgs.namespace;
        expected = "my-ns";
      };
    };
  };

  # ---- directory overrides ----
  dirOverrides = {
    tests = {
      "packagesDir override changes what packages discovers" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              packagesDir = "modules";
              autoInject = false;
            };
            pkgs = result.packages."x86_64-linux" or { };
          in
          {
            hasNixos = pkgs ? "nixos";
            hasHello = pkgs ? "hello";
          };
        expected = {
          hasNixos = true;
          hasHello = false;
        };
      };
      "checksDir override changes what checks discovers" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = fixturesDir;
              checksDir = "packages";
              autoInject = false;
            };
          in
          result.checks."x86_64-linux" ? "hello";
        expected = true;
      };
    };
  };

  # ---- empty project ----
  noDirs = {
    tests = {
      "empty project still produces module outputs" = {
        expr =
          let
            result = mkFlake {
              inputs = inputsBase;
              src = ../unit;
              autoInject = false;
            };
          in
          {
            hasNixosModules = result ? nixosModules;
            hasDarwinModules = result ? darwinModules;
            hasHomeModules = result ? homeModules;
            hasSystems = result ? nixosConfigurations;
          };
        expected = {
          hasNixosModules = true;
          hasDarwinModules = true;
          hasHomeModules = true;
          hasSystems = false;
        };
      };
    };
  };
}
