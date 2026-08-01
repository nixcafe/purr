# Unit tests for lib/hydraJobs.nix.
{ lib }:
let
  attrsMod = import ../../lib/attrs.nix;

  hj = import ../../lib/hydraJobs.nix {
    inherit lib;
    attrs = attrsMod;
  };

  confs = import ../../lib/configs.nix {
    inherit lib;
  };

  inherit (hj)
    buildHydraJobs
    configOutputs
    filterSystems
    hydraJobsFromDir
    mirrorOutputs
    ;

  # imagesFromConfigs is not exported by hydraJobs.nix; it lives in configs.nix.
  inherit (confs) imagesFromConfigs;

  fixturesDir = ../fixtures;

  mockSystemPkgs = {
    "x86_64-linux" = {
      system = "x86_64-linux";
    };
    "aarch64-linux" = {
      system = "aarch64-linux";
    };
    "aarch64-darwin" = {
      system = "aarch64-darwin";
    };
  };
in
{
  # ---- filterSystems ----
  filterSystems = {
    tests = {
      "null systems passes attrs through unchanged" = {
        expr = filterSystems {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
        } null;
        expected = {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
        };
      };
      "keeps only the listed systems" = {
        expr = filterSystems {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
          "aarch64-darwin" = 3;
        } [ "aarch64-linux" ];
        expected = {
          "aarch64-linux" = 2;
        };
      };
      "returns empty when no systems match" = {
        expr = filterSystems {
          "x86_64-linux" = 1;
        } [ "aarch64-linux" ];
        expected = { };
      };
    };
  };

  # ---- mirrorOutputs ----
  mirrorOutputs = {
    tests = {
      "mirrors named per-system outputs" = {
        expr = mirrorOutputs {
          checks = {
            "x86_64-linux" = {
              lint = "pass";
            };
          };
        } [ "checks" ] null;
        expected = {
          checks = {
            "x86_64-linux" = {
              lint = "pass";
            };
          };
        };
      };
      "filters mirrored outputs by systems" = {
        expr = mirrorOutputs {
          checks = {
            "x86_64-linux" = {
              a = 1;
            };
            "aarch64-linux" = {
              b = 2;
            };
          };
        } [ "checks" ] [ "x86_64-linux" ];
        expected = {
          checks = {
            "x86_64-linux" = {
              a = 1;
            };
          };
        };
      };
      "drops a mirror that becomes empty after filtering" = {
        expr = mirrorOutputs {
          checks."x86_64-linux".a = 1;
        } [ "checks" ] [ "aarch64-linux" ];
        expected = { };
      };
      "drops mirrors whose per-system content is empty" = {
        expr =
          mirrorOutputs
            {
              packages."x86_64-linux" = { };
              checks."x86_64-linux".lint = "pass";
            }
            [
              "packages"
              "checks"
            ]
            null;
        expected = {
          checks."x86_64-linux".lint = "pass";
        };
      };
      "empty names returns empty attrs" = {
        expr = mirrorOutputs {
          checks."x86_64-linux".a = 1;
        } [ ] null;
        expected = { };
      };
      "missing output name is skipped" = {
        expr =
          mirrorOutputs
            {
              checks."x86_64-linux".a = 1;
            }
            [
              "checks"
              "packages"
            ]
            null;
        expected = {
          checks."x86_64-linux".a = 1;
        };
      };
    };
  };

  # ---- configOutputs ----
  configOutputs = {
    tests = {
      "groups nixosConfigs by the configSystems map" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  config.system.build.toplevel = "toplevel-host1";
                };
                host2 = {
                  config.system.build.toplevel = "toplevel-host2";
                };
              };
              configSystems.nixosConfigurations = {
                host1 = "x86_64-linux";
                host2 = "aarch64-linux";
              };
            };
          in
          (configOutputs sysCfg { } [ "nixosConfigs" ] null { }).nixosConfigs;
        expected = {
          "x86_64-linux" = {
            host1 = "toplevel-host1";
          };
          "aarch64-linux" = {
            host2 = "toplevel-host2";
          };
        };
      };
      "filters nixosConfigs by systems" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  config.system.build.toplevel = "toplevel-host1";
                };
                host2 = {
                  config.system.build.toplevel = "toplevel-host2";
                };
              };
              configSystems.nixosConfigurations = {
                host1 = "x86_64-linux";
                host2 = "aarch64-linux";
              };
            };
          in
          (configOutputs sysCfg { } [ "nixosConfigs" ] [ "x86_64-linux" ] { }).nixosConfigs;
        expected = {
          "x86_64-linux" = {
            host1 = "toplevel-host1";
          };
        };
      };
      "groups darwinConfigs by the configSystems map" = {
        expr =
          let
            sysCfg = {
              darwinConfigurations = {
                mac1 = {
                  system = "darwin-mac1";
                };
                mac2 = {
                  system = "darwin-mac2";
                };
              };
              configSystems.darwinConfigurations = {
                mac1 = "aarch64-darwin";
                mac2 = "x86_64-darwin";
              };
            };
          in
          (configOutputs sysCfg { } [ "darwinConfigs" ] null { }).darwinConfigs;
        expected = {
          "aarch64-darwin" = {
            mac1 = "darwin-mac1";
          };
          "x86_64-darwin" = {
            mac2 = "darwin-mac2";
          };
        };
      };
      "groups homeConfigs by the homeSystems map" = {
        expr =
          let
            homes = {
              "alice@host1" = {
                activationPackage = "activation-alice";
              };
              "bob@host2" = {
                activationPackage = "activation-bob";
              };
            };
          in
          (configOutputs { } homes [ "homeConfigs" ] null {
            "alice@host1" = "x86_64-linux";
            "bob@host2" = "aarch64-linux";
          }).homeConfigs;
        expected = {
          "x86_64-linux" = {
            "alice@host1" = "activation-alice";
          };
          "aarch64-linux" = {
            "bob@host2" = "activation-bob";
          };
        };
      };
      "filters homeConfigs by systems" = {
        expr =
          let
            homes = {
              "alice@host1" = {
                activationPackage = "activation-alice";
              };
              "bob@host2" = {
                activationPackage = "activation-bob";
              };
            };
          in
          (configOutputs { } homes [ "homeConfigs" ] [ "x86_64-linux" ] {
            "alice@host1" = "x86_64-linux";
            "bob@host2" = "aarch64-linux";
          }).homeConfigs;
        expected = {
          "x86_64-linux" = {
            "alice@host1" = "activation-alice";
          };
        };
      };
      "combines nixos, darwin, and home groups" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
              darwinConfigurations = {
                mac1 = {
                  system = "darwin-mac1";
                };
              };
              configSystems = {
                nixosConfigurations.host1 = "x86_64-linux";
                darwinConfigurations.mac1 = "aarch64-darwin";
              };
            };
            homes = {
              "alice@host1" = {
                activationPackage = "activation-alice";
              };
            };
            result =
              configOutputs sysCfg homes
                [
                  "nixosConfigs"
                  "darwinConfigs"
                  "homeConfigs"
                ]
                null
                {
                  "alice@host1" = "x86_64-linux";
                };
          in
          {
            nixos = result.nixosConfigs."x86_64-linux".host1 or null;
            darwin = result.darwinConfigs."aarch64-darwin".mac1 or null;
            home = result.homeConfigs."x86_64-linux"."alice@host1" or null;
          };
        expected = {
          nixos = "toplevel-host1";
          darwin = "darwin-mac1";
          home = "activation-alice";
        };
      };
      # Regression guard: configOutputs must group purely from the pre-known
      # system maps (configSystems / homeSystems) and never read cfg.pkgs.
      # Reading cfg.pkgs.system used to force a full nixpkgs/stdenv evaluation
      # per config just to obtain the system — the `throw` sentinels below fail
      # loudly if that behavior is ever reintroduced.
      "uses configSystems map so cfg.pkgs is never forced" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs = throw "pkgs must not be forced";
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
              configSystems.nixosConfigurations.host1 = "x86_64-linux";
            };
            homes = {
              "alice@host1" = {
                pkgs = throw "pkgs must not be forced";
                activationPackage = "activation-alice";
              };
            };
            result =
              configOutputs sysCfg homes
                [
                  "nixosConfigs"
                  "homeConfigs"
                ]
                null
                {
                  "alice@host1" = "x86_64-linux";
                };
          in
          {
            nixos = result.nixosConfigs."x86_64-linux".host1;
            home = result.homeConfigs."x86_64-linux"."alice@host1";
          };
        expected = {
          nixos = "toplevel-host1";
          home = "activation-alice";
        };
      };
      "configSystems map is filtered by systems" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs = throw "pkgs must not be forced";
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
              configSystems.nixosConfigurations.host1 = "x86_64-linux";
            };
          in
          {
            shown = (configOutputs sysCfg { } [ "nixosConfigs" ] [ "x86_64-linux" ] { }).nixosConfigs;
            filteredOut =
              (configOutputs sysCfg { } [ "nixosConfigs" ] [ "aarch64-linux" ] { }).nixosConfigs or { };
          };
        expected = {
          shown = {
            "x86_64-linux" = {
              host1 = "toplevel-host1";
            };
          };
          filteredOut = { };
        };
      };
      "unknown group name returns empty" = {
        expr = configOutputs { } { } [ "nonexistent" ] null { };
        expected = { };
      };
      "empty configs return empty" = {
        expr = configOutputs { } { } [ "nixosConfigs" ] null { };
        expected = { };
      };
    };
  };

  # ---- hydraJobsFromDir ----
  hydraJobsFromDir = {
    tests = {
      "discovers build jobs for every system" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          {
            systems = builtins.attrNames (result.build or { });
            hello = result.build."x86_64-linux".hello or null;
            goodbye = result.build."aarch64-darwin".goodbye or null;
          };
        expected = {
          systems = [
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ];
          hello = "hello-x86_64-linux";
          goodbye = "goodbye-aarch64-darwin";
        };
      };
      "test group only appears for systems with non-null jobs" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          {
            groups = builtins.attrNames result;
            testSystems = builtins.attrNames (result.test or { });
          };
        expected = {
          groups = [
            "build"
            "test"
          ];
          testSystems = [ "x86_64-linux" ];
        };
      };
      "test.unit yields tests-pass on x86_64-linux only" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          {
            x86 = result.test."x86_64-linux".unit or null;
            hasAarch64 = result.test ? "aarch64-linux";
          };
        expected = {
          x86 = "tests-pass";
          hasAarch64 = false;
        };
      };
      "group with only null jobs is excluded" = {
        expr = (hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { }) ? "nope";
        expected = false;
      };
      "filters to listed systems" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" [
              "x86_64-linux"
            ] mockSystemPkgs lib null { } { };
          in
          {
            systems = builtins.attrNames (result.build or { });
            hasAarch64 = result.build ? "aarch64-linux";
          };
        expected = {
          systems = [ "x86_64-linux" ];
          hasAarch64 = false;
        };
      };
      "null dir returns empty" = {
        expr = hydraJobsFromDir fixturesDir null null mockSystemPkgs lib null { } { };
        expected = { };
      };
      "missing dir returns empty" = {
        expr = hydraJobsFromDir fixturesDir "nonexistent" null mockSystemPkgs lib null { } { };
        expected = { };
      };
    };
  };

  # ---- imagesFromConfigs (imported from configs.nix) ----
  imagesFromConfigs = {
    tests = {
      "extracts declared image formats from imageRecipes" = {
        expr = imagesFromConfigs {
          host = {
            system = "x86_64-linux";
            images = [ "iso" ];
            cfg = {
              config.system.build.images.iso = "iso-drv";
            };
          };
        } null;
        expected = {
          host = {
            iso = "iso-drv";
          };
        };
      };
      "structure is lazy: names come from declared formats" = {
        expr =
          let
            result = imagesFromConfigs {
              host = {
                system = "x86_64-linux";
                images = [
                  "iso"
                  "qemu"
                ];
                cfg = {
                  config.system.build.images.iso = "iso-drv";
                };
              };
            } null;
          in
          {
            names = builtins.attrNames result.host;
            iso = result.host.iso;
            missingThrows = (builtins.tryEval result.host.qemu).success;
          };
        expected = {
          names = [
            "iso"
            "qemu"
          ];
          iso = "iso-drv";
          missingThrows = false;
        };
      };
      "filters imageRecipes by system" = {
        expr =
          let
            recipes = {
              x86 = {
                system = "x86_64-linux";
                images = [ "iso" ];
                cfg = {
                  config.system.build.images.iso = "iso-x86";
                };
              };
              arm = {
                system = "aarch64-linux";
                images = [ "iso" ];
                cfg = {
                  config.system.build.images.iso = "iso-arm";
                };
              };
            };
          in
          {
            hasX86 = (imagesFromConfigs recipes [ "x86_64-linux" ]) ? x86;
            hasArm = (imagesFromConfigs recipes [ "x86_64-linux" ]) ? arm;
          };
        expected = {
          hasX86 = true;
          hasArm = false;
        };
      };
      "returns empty when no recipes match" = {
        expr = imagesFromConfigs { } null;
        expected = { };
      };
    };
  };

  # ---- buildHydraJobs ----
  buildHydraJobs = {
    tests = {
      "combines dir jobs, mirrors, config outputs, images, and extra" = {
        expr =
          let
            result = buildHydraJobs {
              src = fixturesDir;
              hydraJobsDir = "hydraJobs";
              hydraSystems = [ "x86_64-linux" ];
              hydraJobsInclude = [
                "checks"
                "nixosConfigs"
              ];
              hydraJobsExtra = {
                extraTop = {
                  "x86_64-linux" = {
                    custom = "extra";
                  };
                };
              };
              systemPkgs = mockSystemPkgs;
              perSystemOutputs = {
                checks = {
                  "x86_64-linux" = {
                    myCheck = "check-pass";
                  };
                };
              };
              systemConfigs = {
                nixosConfigurations.host1 = {
                  config.system.build.toplevel = "toplevel-host1";
                };
                configSystems.nixosConfigurations.host1 = "x86_64-linux";
                imageRecipes.iso = {
                  system = "x86_64-linux";
                  images = [ "iso" ];
                  cfg = {
                    config.system.build.images.iso = "iso-drv";
                  };
                };
              };
              homeConfigs = { };
              inherit lib;
              namespace = null;
              inputs = { };
              extraArgs = { };
            };
          in
          {
            dirJob = result.build."x86_64-linux".hello or null;
            check = result.checks."x86_64-linux".myCheck or null;
            nixos = result.nixosConfigs."x86_64-linux".host1 or null;
            image = result.images.iso.iso or null;
            extra = result.extraTop."x86_64-linux".custom or null;
          };
        expected = {
          dirJob = "hello-x86_64-linux";
          check = "check-pass";
          nixos = "toplevel-host1";
          image = "iso-drv";
          extra = "extra";
        };
      };
      "auto-detects include when null" = {
        expr =
          let
            result = buildHydraJobs {
              src = fixturesDir;
              hydraJobsDir = null;
              hydraSystems = null;
              hydraJobsInclude = null;
              hydraJobsExtra = { };
              systemPkgs = mockSystemPkgs;
              perSystemOutputs = {
                checks = {
                  "x86_64-linux" = {
                    myCheck = "check-pass";
                  };
                };
                packages = {
                  "x86_64-linux" = {
                    myPkg = "pkg-pass";
                  };
                };
              };
              systemConfigs = {
                nixosConfigurations.host1 = {
                  config.system.build.toplevel = "toplevel-host1";
                };
                configSystems.nixosConfigurations.host1 = "x86_64-linux";
              };
              homeConfigs = {
                "alice@host1" = {
                  activationPackage = "activation-alice";
                };
              };
              homeSystems."alice@host1" = "x86_64-linux";
              inherit lib;
              namespace = null;
              inputs = { };
              extraArgs = { };
            };
          in
          {
            checks = result.checks."x86_64-linux".myCheck or null;
            packages = result.packages."x86_64-linux".myPkg or null;
            nixosConfigs = result.nixosConfigs."x86_64-linux".host1 or null;
            homeConfigs = result.homeConfigs."x86_64-linux"."alice@host1" or null;
          };
        expected = {
          checks = "check-pass";
          packages = "pkg-pass";
          nixosConfigs = "toplevel-host1";
          homeConfigs = "activation-alice";
        };
      };
      "explicit include overrides auto-detection" = {
        expr =
          let
            result = buildHydraJobs {
              src = fixturesDir;
              hydraJobsDir = null;
              hydraSystems = null;
              hydraJobsInclude = [ "checks" ];
              hydraJobsExtra = { };
              systemPkgs = mockSystemPkgs;
              perSystemOutputs = {
                checks = {
                  "x86_64-linux" = {
                    myCheck = "check-pass";
                  };
                };
                packages = {
                  "x86_64-linux" = {
                    myPkg = "pkg-pass";
                  };
                };
              };
              systemConfigs = { };
              homeConfigs = { };
              inherit lib;
              namespace = null;
              inputs = { };
              extraArgs = { };
            };
          in
          {
            hasChecks = result ? checks;
            hasPackages = result ? packages;
          };
        expected = {
          hasChecks = true;
          hasPackages = false;
        };
      };
    };
  };
}
