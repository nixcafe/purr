# Integration tests for the flake-parts module (`flake-module.nix`).
#
# The module is evaluated through the REAL `lib.evalModules` (with `flake` and
# `perSystem` options declared, mirroring flake-parts), and the generated
# `config.flake` / `config.perSystem` outputs are verified against the same
# full-featured project used by the mkFlake integration test.
{ lib }:
let
  inherit (lib)
    attrNames
    length
    sort
    ;

  harness = import ./harness.nix {
    inherit lib;
  };

  inherit (harness) inputs;

  projectDir = ./project;

  flakeModule = import ../../flake-module.nix;

  eval = lib.evalModules {
    modules = [
      flakeModule
      {
        options.flake = lib.mkOption {
          type = lib.types.raw;
        };
        options.perSystem = lib.mkOption {
          type = lib.types.raw;
        };
      }
      {
        purr.enable = true;
        purr.src = projectDir;
        purr.namespace = "demo";
        purr.bundleModules = true;
        purr.packagesByName = true;
        purr.hosts.server.meta = {
          tier = "prod";
          region = "us-east";
        };
      }
    ];
    specialArgs = {
      inherit inputs;
    };
  };

  flake = eval.config.flake;

  perSystem = system: (eval.config.perSystem { inherit system; }).config;

  hydraEval = lib.evalModules {
    modules = [
      flakeModule
      {
        options.flake = lib.mkOption {
          type = lib.types.raw;
        };
        options.perSystem = lib.mkOption {
          type = lib.types.raw;
        };
      }
      {
        purr.enable = true;
        purr.src = projectDir;
        purr.namespace = "demo";
        purr.hosts.server.meta = {
          tier = "prod";
          region = "us-east";
        };
        purr.hydraJobs = {
          enable = true;
          as = "builds";
          systems = [ "x86_64-linux" ];
        };
      }
    ];
    specialArgs = {
      inherit inputs;
    };
  };

  hydraFlake = hydraEval.config.flake;
in
{
  flakeOutputs = {
    tests = {
      "exposes nixosConfigurations" = {
        expr = attrNames (flake.nixosConfigurations or { });
        expected = [ "server" ];
      };
      "exposes darwinConfigurations" = {
        expr = attrNames (flake.darwinConfigurations or { });
        expected = [ "macbook" ];
      };
      "exposes image-only host via images" = {
        expr = flake.images.iso or { };
        expected = {
          iso = "iso-drv";
        };
      };
      "exposes module outputs" = {
        expr = sort (a: b: a < b) (attrNames (flake.nixosModules or { }));
        expected = [
          "base"
          "common"
          "default"
          "inputs-ref"
          "services"
        ];
      };
      "exposes homeConfigurations" = {
        expr = sort (a: b: a < b) (attrNames (flake.homeConfigurations or { }));
        expected = [
          "alice@macbook"
          "alice@server"
          "root@server"
        ];
      };
      "exposes overlays and templates" = {
        expr = {
          hasOverlay = flake.overlays ? "custom";
          hasTemplate = flake.templates ? "rust";
        };
        expected = {
          hasOverlay = true;
          hasTemplate = true;
        };
      };
      "exposes namespaced lib" = {
        expr = {
          rootMarker = flake.lib.demo.rootMarker;
          add = flake.lib.demo.math.add 1 2;
          upper = flake.lib.demo.strings.upper.upper "ab";
        };
        expected = {
          rootMarker = "root:demo";
          add = 3;
          upper = "AB";
        };
      };
    };
  };

  systemEval = {
    tests = {
      "system config is evaluated through real module system" = {
        expr = {
          hostName = flake.nixosConfigurations.server.config.networking.hostName;
          stateVersion = flake.nixosConfigurations.server.config.system.stateVersion;
          greeting = flake.nixosConfigurations.server.config.demo.base.greeting;
        };
        expected = {
          hostName = "server";
          stateVersion = "24.11";
          greeting = "HI";
        };
      };
      "module sees the defining flake's inputs" = {
        expr = flake.nixosConfigurations.server.config.demo.inputsRef.hasDefiningInputs;
        expected = true;
      };
      "system specialArgs carry namespace and purr metadata" = {
        expr = {
          namespace = flake.nixosConfigurations.server.specialArgs.namespace;
          purrName = flake.nixosConfigurations.server.specialArgs.purr.meta.name;
          metaTier = flake.nixosConfigurations.server.specialArgs.purr.meta.tier;
          metaRegion = flake.nixosConfigurations.server.specialArgs.purr.meta.region;
        };
        expected = {
          namespace = "demo";
          purrName = "server";
          metaTier = "prod";
          metaRegion = "us-east";
        };
      };
    };
  };

  perSystemOutputs = {
    tests = {
      "checks discovered" = {
        expr = (perSystem "x86_64-linux").checks.lint;
        expected = "check-x86_64-linux";
      };
      "packages discovered (regular + by-name)" = {
        expr = sort (a: b: a < b) (attrNames ((perSystem "x86_64-linux").packages or { }));
        expected = [
          "cowsay"
          "hello"
        ];
      };
      "devShells discovered" = {
        expr = (perSystem "x86_64-linux").devShells.dev._type;
        expected = "mkShell";
      };
      "formatter discovered" = {
        expr = (perSystem "x86_64-linux").formatter;
        expected = "hello-drv-x86_64-linux";
      };
      "apps discovered" = {
        expr = (perSystem "x86_64-linux").apps.run.program;
        expected = "hello-drv-x86_64-linux/bin/hello";
      };
      "legacyPackages discovered" = {
        expr = (perSystem "x86_64-linux").legacyPackages.old;
        expected = "legacy-x86_64-linux";
      };
      "per-system outputs discovered for every system" = {
        expr = (perSystem "aarch64-darwin").checks.lint;
        expected = "check-aarch64-darwin";
      };
    };
  };

  namespaceBridge = {
    tests = {
      "home-manager.users populated for linked homes" = {
        expr = attrNames (flake.nixosConfigurations.server.config."home-manager".users or { });
        expected = [
          "alice"
          "root"
        ];
      };
      "bridge config forwarded to alice" = {
        expr =
          let
            users = flake.nixosConfigurations.server.config."home-manager".users;
            bridge = builtins.filter (
              m:
              builtins.isAttrs m && m ? config && m.config ? home && m.config.home.packages or [ ] == [ "cowsay" ]
            ) (users.alice.imports or [ ]);
          in
          length bridge;
        expected = 1;
      };
    };
  };

  hydraJobsAs = {
    tests = {
      "renamed output present, hydraJobs absent" = {
        expr = {
          hasBuilds = hydraFlake ? "builds";
          hasHydraJobs = hydraFlake ? "hydraJobs";
        };
        expected = {
          hasBuilds = true;
          hasHydraJobs = false;
        };
      };
      "renamed output carries mirrored jobs" = {
        expr = hydraFlake.builds.nixosConfigurations."x86_64-linux".server;
        expected = "toplevel-server";
      };
    };
  };
}
