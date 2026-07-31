# Tests for lib/hydraJobs.nix — direct eval verification
{
  lib,
  ...
}:
let
  inherit (lib)
    attrNames
    foldl'
    ;

  attrsMod = import ../lib/attrs.nix;

  hj = import ../lib/hydraJobs.nix {
    inherit lib;
    attrs = attrsMod;
  };

  inherit (hj)
    buildHydraJobs
    configOutputs
    filterSystems
    hydraJobsFromDir
    imagesFromConfigs
    mirrorOutputs
    ;

  fixturesDir = ./fixtures;

  mkMockPkgs = system: {
    inherit system;
    stdenv = "stdenv-${system}";
  };

  mockSystemPkgs = foldl' (acc: system: acc // { ${system} = mkMockPkgs system; }) { } [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
in
{
  # ---- filterSystems ----
  filterSystems = {
    tests = {
      "null systems passes through" = {
        expr = filterSystems {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
        } null;
        expected = {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
        };
      };
      "filters to specified systems" = {
        expr = filterSystems {
          "x86_64-linux" = 1;
          "aarch64-linux" = 2;
          "aarch64-darwin" = 3;
        } [ "x86_64-linux" ];
        expected = {
          "x86_64-linux" = 1;
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
      "mirrors checks output" = {
        expr = mirrorOutputs {
          checks = {
            "x86_64-linux".myTest = "pass";
          };
        } [ "checks" ] null;
        expected = {
          checks = {
            "x86_64-linux".myTest = "pass";
          };
        };
      };
      "filters mirrors by systems" = {
        expr = mirrorOutputs {
          checks = {
            "x86_64-linux".a = 1;
            "aarch64-linux".b = 2;
          };
        } [ "checks" ] [ "x86_64-linux" ];
        expected = {
          checks = {
            "x86_64-linux".a = 1;
          };
        };
      };
      "empty names returns empty attrs" = {
        expr = mirrorOutputs { checks.x86_64-linux.x = 1; } [ ] null;
        expected = { };
      };
      "multiple names mirrored" = {
        expr =
          let
            result =
              mirrorOutputs
                {
                  checks = {
                    "x86_64-linux".a = 1;
                  };
                  packages = {
                    "x86_64-linux".b = 2;
                  };
                }
                [
                  "checks"
                  "packages"
                ]
                null;
          in
          attrNames result;
        expected = [
          "checks"
          "packages"
        ];
      };
    };
  };

  # ---- configOutputs ----
  configOutputs = {
    tests = {
      "groups nixosConfigs by system" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host1";
                };
                host2 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host2";
                };
                host3 = {
                  pkgs.system = "aarch64-linux";
                  config.system.build.toplevel = "toplevel-host3";
                };
              };
            };
            result = configOutputs sysCfg { } [ "nixosConfigs" ] null;
          in
          result.nixosConfigs or { };
        expected = {
          "x86_64-linux" = {
            host1 = "toplevel-host1";
            host2 = "toplevel-host2";
          };
          "aarch64-linux" = {
            host3 = "toplevel-host3";
          };
        };
      };
      "filters nixosConfigs by systems" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host1";
                };
                host2 = {
                  pkgs.system = "aarch64-linux";
                  config.system.build.toplevel = "toplevel-host2";
                };
              };
            };
            result =
              configOutputs sysCfg { }
                [
                  "nixosConfigs"
                ]
                [ "x86_64-linux" ];
          in
          result.nixosConfigs or { };
        expected = {
          "x86_64-linux" = {
            host1 = "toplevel-host1";
          };
        };
      };
      "groups darwinConfigs by system" = {
        expr =
          let
            sysCfg = {
              darwinConfigurations = {
                mac1 = {
                  pkgs.system = "aarch64-darwin";
                  system = "darwin-system-mac1";
                };
                mac2 = {
                  pkgs.system = "x86_64-darwin";
                  system = "darwin-system-mac2";
                };
              };
            };
            result = configOutputs sysCfg { } [ "darwinConfigs" ] null;
          in
          result.darwinConfigs or { };
        expected = {
          "aarch64-darwin" = {
            mac1 = "darwin-system-mac1";
          };
          "x86_64-darwin" = {
            mac2 = "darwin-system-mac2";
          };
        };
      };
      "groups homeConfigs by system" = {
        expr =
          let
            homes = {
              "user1@host1" = {
                pkgs.system = "x86_64-linux";
                activationPackage = "activation-user1";
              };
              "user2@host2" = {
                pkgs.system = "aarch64-linux";
                activationPackage = "activation-user2";
              };
            };
            result = configOutputs { } homes [ "homeConfigs" ] null;
          in
          result.homeConfigs or { };
        expected = {
          "x86_64-linux" = {
            "user1@host1" = "activation-user1";
          };
          "aarch64-linux" = {
            "user2@host2" = "activation-user2";
          };
        };
      };
      "filters homeConfigs by systems" = {
        expr =
          let
            homes = {
              "user1@host1" = {
                pkgs.system = "x86_64-linux";
                activationPackage = "activation-user1";
              };
              "user2@host2" = {
                pkgs.system = "aarch64-linux";
                activationPackage = "activation-user2";
              };
            };
            result =
              configOutputs { } homes
                [
                  "homeConfigs"
                ]
                [ "x86_64-linux" ];
          in
          result.homeConfigs or { };
        expected = {
          "x86_64-linux" = {
            "user1@host1" = "activation-user1";
          };
        };
      };
      "multiple config types combined" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
            };
            homes = {
              "user1@host1" = {
                pkgs.system = "x86_64-linux";
                activationPackage = "activation-user1";
              };
            };
            result = configOutputs sysCfg homes [
              "nixosConfigs"
              "homeConfigs"
            ] null;
          in
          {
            hasNixos = result ? nixosConfigs;
            hasHome = result ? homeConfigs;
          };
        expected = {
          hasNixos = true;
          hasHome = true;
        };
      };
      "unknown name returns empty" = {
        expr = configOutputs { } { } [ "nonexistent" ] null;
        expected = { };
      };
      "empty configs return empty" = {
        expr = configOutputs { } { } [ "nixosConfigs" ] null;
        expected = { };
      };
      "empty names returns empty" = {
        expr =
          let
            sysCfg = {
              nixosConfigurations = {
                host1 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
            };
          in
          configOutputs sysCfg { } [ ] null;
        expected = { };
      };
    };
  };

  # ---- hydraJobsFromDir ----
  hydraJobsFromDir = {
    tests = {
      "discovers jobs from directory" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          result.build.x86_64-linux.hello or null;
        expected = "hello-x86_64-linux";
      };
      "filters by systems" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" [
              "x86_64-linux"
            ] mockSystemPkgs lib null { } { };
          in
          {
            hasX86 = result.build.x86_64-linux.hello or null;
            hasAarch64 = result.build ? "aarch64-linux";
          };
        expected = {
          hasX86 = "hello-x86_64-linux";
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
      "null job is skipped" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" [
              "x86_64-linux"
            ] mockSystemPkgs lib null { } { };
          in
          result ? "nope";
        expected = false;
      };
      "job returning null for some systems" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          {
            hasX86 = result ? "test" && result.test ? "x86_64-linux";
            hasAarch64 = if result ? "test" then result.test ? "aarch64-linux" else false;
          };
        expected = {
          hasX86 = true;
          hasAarch64 = false;
        };
      };
      "group with all null jobs excluded" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          result ? "nope";
        expected = false;
      };
    };
  };

  # ---- imagesFromConfigs ----
  imagesFromConfigs = {
    tests = {
      "extracts declared NixOS image formats" = {
        expr =
          let
            mockConfig = {
              nixosConfigurations = {
                myserver = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [
                      "iso"
                      "qemu"
                    ];
                    system.build.images = {
                      iso = "iso-drv";
                      qemu = "qemu-drv";
                      raw = "raw-drv";
                    };
                  };
                };
              };
            };
            result = imagesFromConfigs mockConfig null;
          in
          result.myserver or { };
        expected = {
          iso = "iso-drv";
          qemu = "qemu-drv";
        };
      };
      "skips undeclared formats" = {
        expr =
          let
            mockConfig = {
              nixosConfigurations = {
                myserver = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [ "iso" ];
                    system.build.images = {
                      iso = "iso-drv";
                      qemu = "qemu-drv";
                    };
                  };
                };
              };
            };
            result = imagesFromConfigs mockConfig null;
          in
          result.myserver or { };
        expected = {
          iso = "iso-drv";
        };
      };
      "host without purr.images has no image jobs" = {
        expr =
          let
            mockConfig = {
              nixosConfigurations = {
                myserver = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [ ];
                    system.build.images = {
                      iso = "iso-drv";
                    };
                  };
                };
              };
            };
            result = imagesFromConfigs mockConfig null;
          in
          result ? myserver;
        expected = false;
      };
      "filters by system" = {
        expr =
          let
            mockConfig = {
              nixosConfigurations = {
                x86 = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [ "iso" ];
                    system.build.images = {
                      iso = "iso-x86";
                    };
                  };
                };
                arm = {
                  system = "aarch64-linux";
                  config = {
                    purr.images = [ "iso" ];
                    system.build.images = {
                      iso = "iso-arm";
                    };
                  };
                };
              };
            };
            result = imagesFromConfigs mockConfig [ "x86_64-linux" ];
          in
          {
            hasX86 = result ? x86;
            hasArm = result ? arm;
          };
        expected = {
          hasX86 = true;
          hasArm = false;
        };
      };
      "returns empty for no systems" = {
        expr =
          let
            mockConfig = { };
          in
          imagesFromConfigs mockConfig null;
        expected = { };
      };
    };
  };

  # ---- buildHydraJobs (integration) ----
  buildHydraJobs = {
    tests = {
      "combines dir, mirror, images, and extra" = {
        expr =
          let
            perSys = {
              checks = {
                "x86_64-linux".myCheck = "check-pass";
              };
            };
            sysConfigs = {
              nixosConfigurations = {
                myserver = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [ "iso" ];
                    system.build.images = {
                      iso = "iso-drv";
                    };
                  };
                };
              };
            };
            result = buildHydraJobs {
              src = fixturesDir;
              hydraJobsDir = "hydraJobs";
              hydraSystems = [ "x86_64-linux" ];
              hydraJobsInclude = [ "checks" ];
              hydraJobsExtra = {
                extraTop = {
                  "x86_64-linux".custom = "extra";
                };
              };
              systemPkgs = mockSystemPkgs;
              perSystemOutputs = perSys;
              systemConfigs = sysConfigs;
              inherit lib;
              namespace = null;
              inputs = { };
              extraArgs = { };
            };
          in
          {
            hasBuild = result.build.x86_64-linux.hello or null;
            hasChecks = result.checks.x86_64-linux.myCheck or null;
            hasImages = result.images.myserver.iso or null;
            hasExtra = result.extraTop.x86_64-linux.custom or null;
          };
        expected = {
          hasBuild = "hello-x86_64-linux";
          hasChecks = "check-pass";
          hasImages = "iso-drv";
          hasExtra = "extra";
        };
      };
      "auto-detects all available outputs when include is null" = {
        expr =
          let
            perSys = {
              checks = {
                "x86_64-linux".myCheck = "check-pass";
              };
              packages = {
                "x86_64-linux".myPkg = "pkg-pass";
              };
            };
            sysConfigs = {
              nixosConfigurations = {
                host1 = {
                  pkgs.system = "x86_64-linux";
                  config.system.build.toplevel = "toplevel-host1";
                };
              };
            };
            homes = {
              "user1@host1" = {
                pkgs.system = "x86_64-linux";
                activationPackage = "activation-user1";
              };
            };
            result = buildHydraJobs {
              src = fixturesDir;
              hydraJobsDir = null;
              hydraSystems = null;
              hydraJobsInclude = null;
              hydraJobsExtra = { };
              systemPkgs = mockSystemPkgs;
              perSystemOutputs = perSys;
              systemConfigs = sysConfigs;
              homeConfigs = homes;
              inherit lib;
              namespace = null;
              inputs = { };
              extraArgs = { };
            };
          in
          {
            hasChecks = result.checks.x86_64-linux.myCheck or null;
            hasPackages = result.packages.x86_64-linux.myPkg or null;
            hasNixos = result.nixosConfigs.x86_64-linux.host1 or null;
            hasHome = result.homeConfigs.x86_64-linux."user1@host1" or null;
          };
        expected = {
          hasChecks = "check-pass";
          hasPackages = "pkg-pass";
          hasNixos = "toplevel-host1";
          hasHome = "activation-user1";
        };
      };
    };
  };

  # ---- direct eval tests (self-verifying) ----
  directHydraJobs = {
    tests = {
      "hydraJobsFromDir discovers multiple groups" = {
        expr =
          let
            result = hydraJobsFromDir fixturesDir "hydraJobs" null mockSystemPkgs lib null { } { };
          in
          {
            groups = builtins.sort (a: b: a < b) (attrNames result);
            buildJobs = builtins.sort (a: b: a < b) (attrNames (result.build or { }));
            testSystems = builtins.sort (a: b: a < b) (attrNames (result.test or { }));
          };
        expected = {
          groups = [ "build" ];
          buildJobs = [
            "aarch64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ];
          testSystems = [ "x86_64-linux" ];
        };
      };
      "imagesFromConfigs with image uses lazy check" = {
        expr =
          let
            mockConfig = {
              nixosConfigurations = {
                host1 = {
                  system = "x86_64-linux";
                  config = {
                    purr.images = [
                      "iso"
                      "nonexistent"
                    ];
                    system.build.images = {
                      iso = "iso-dep";
                    };
                  };
                };
              };
            };
            result = imagesFromConfigs mockConfig null;
          in
          result.host1 or { };
        expected = {
          iso = "iso-dep";
        };
      };
    };
  };
}
