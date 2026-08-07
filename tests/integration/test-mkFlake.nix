# Integration tests: run `mkFlake` on a real-feeling project and verify every
# output, including the mutual dependencies between features (systems linked to
# homes, namespace lib injected everywhere, overlays, bundles, hydraJobs
# mirroring) and the special cases (image-only hosts, deployable flag,
# cross-arch home matching, root-user exclusion, by-name packages).
#
# Unlike pure unit tests, `nixosSystem` / `darwinSystem` /
# `homeManagerConfiguration` are mocked to evaluate their module lists through
# the REAL `lib.evalModules` (with minimal shim options), so purr's generated
# configurations are genuinely evaluated and asserted on.
{ lib }:
let
  inherit (lib)
    attrNames
    elem
    filter
    length
    sort
    ;

  harness = import ./harness.nix {
    inherit lib;
  };

  inherit (harness) mkFlake inputs moduleShim;

  projectDir = ./project;

  result = mkFlake {
    inherit inputs;
    src = projectDir;
    namespace = "demo";
    bundleModules = true;
    bundleExtraModules = true;
    packagesByName = true;
    nixpkgsConfig = {
      allowUnfree = true;
    };
    hydraJobs = {
      enable = true;
      systems = [ "x86_64-linux" ];
    };
    hosts.server.meta = {
      tier = "prod";
      region = "us-east";
    };
    outputsBuilder =
      { system, ... }:
      {
        customPerSystem = "custom-${system}";
      };
  };

  server = result.nixosConfigurations.server;
  macbook = result.darwinConfigurations.macbook;

  renamed = mkFlake {
    inherit inputs;
    src = projectDir;
    namespace = "demo";
    hosts.server.meta = {
      tier = "prod";
      region = "us-east";
    };
    hydraJobs = {
      enable = true;
      as = "builds";
      systems = [ "x86_64-linux" ];
    };
  };
in
{
  outputShape = {
    tests = {
      "exposes module outputs" = {
        expr = attrNames result;
        expected = sort (a: b: a < b) [
          "apps"
          "checks"
          "customPerSystem"
          "darwinConfigurations"
          "darwinModules"
          "devShells"
          "formatter"
          "homeConfigurations"
          "homeModules"
          "hydraJobs"
          "images"
          "legacyPackages"
          "lib"
          "nixosConfigurations"
          "nixosModules"
          "overlays"
          "packages"
          "templates"
        ];
      };
    };
  };

  # ---- systems: discovery, linking, metadata ----
  systems = {
    tests = {
      "discovers linux host into nixosConfigurations" = {
        expr = attrNames (result.nixosConfigurations or { });
        expected = [ "server" ];
      };
      "discovers darwin host into darwinConfigurations" = {
        expr = attrNames (result.darwinConfigurations or { });
        expected = [ "macbook" ];
      };
      "server specialArgs has namespace" = {
        expr = server.specialArgs.namespace;
        expected = "demo";
      };
      "server specialArgs has host" = {
        expr = server.specialArgs.host;
        expected = "server";
      };
      "server specialArgs has system" = {
        expr = server.specialArgs.system;
        expected = "x86_64-linux";
      };
      "server specialArgs has namespaced lib" = {
        expr = (server.specialArgs.lib or { }) ? "demo";
        expected = true;
      };
      "server specialArgs purr metadata" = {
        expr = {
          name = server.specialArgs.purr.meta.name;
          arch = server.specialArgs.purr.meta.arch;
          format = server.specialArgs.purr.meta.format;
          archFormat = server.specialArgs.purr.meta.archFormat;
          isLinux = server.specialArgs.purr.meta.isLinux;
          isDarwin = server.specialArgs.purr.meta.isDarwin;
        };
        expected = {
          name = "server";
          arch = "x86_64";
          format = "linux";
          archFormat = "x86_64-linux";
          isLinux = true;
          isDarwin = false;
        };
      };
      "server purr.homes lists linked homes" = {
        expr = sort (a: b: a.user < b.user) server.specialArgs.purr.meta.homes;
        expected = [
          {
            user = "alice";
            host = "server";
          }
          {
            user = "root";
            host = "server";
          }
        ];
      };
      "server purr.systemMetas registers every host including self" = {
        expr = {
          keys = sort (a: b: a < b) (attrNames server.specialArgs.purr.systemMetas or { });
          self = server.specialArgs.purr.systemMetas.server.name;
          macbook = server.specialArgs.purr.systemMetas.macbook.name;
          iso = server.specialArgs.purr.systemMetas.iso.name;
          isoImages = server.specialArgs.purr.systemMetas.iso.images;
        };
        expected = {
          keys = [
            "iso"
            "macbook"
            "server"
          ];
          self = "server";
          macbook = "macbook";
          iso = "iso";
          isoImages = [ "iso" ];
        };
      };
      "darwin specialArgs purr metadata" = {
        expr = {
          name = macbook.specialArgs.purr.meta.name;
          arch = macbook.specialArgs.purr.meta.arch;
          format = macbook.specialArgs.purr.meta.format;
          isDarwin = macbook.specialArgs.purr.meta.isDarwin;
          isLinux = macbook.specialArgs.purr.meta.isLinux;
        };
        expected = {
          name = "macbook";
          arch = "aarch64";
          format = "darwin";
          isDarwin = true;
          isLinux = false;
        };
      };
      "darwin purr.systemMetas includes linux hosts" = {
        expr = {
          server = macbook.specialArgs.purr.systemMetas.server.name;
          iso = macbook.specialArgs.purr.systemMetas.iso.name;
        };
        expected = {
          server = "server";
          iso = "iso";
        };
      };
    };
  };

  # ---- system configs are REALLY evaluated ----
  systemEvaluation = {
    tests = {
      "auto-injects networking.hostName (mkDefault)" = {
        expr = server.config.networking.hostName;
        expected = "server";
      };
      "host module evaluated stateVersion" = {
        expr = server.config.system.stateVersion;
        expected = "24.11";
      };
      "toplevel is exposed for hydraJobs" = {
        expr = server.config.system.build.toplevel;
        expected = "toplevel-server";
      };
      "namespace lib usable inside system module" = {
        expr = server.config.demo.server.answer;
        expected = 42;
      };
      "bundled discovered module evaluates with namespace lib" = {
        expr = server.config.demo.base.greeting;
        expected = "HI";
      };
      "shared module merged into system config" = {
        expr = server.config.demo.shared.marker;
        expected = true;
      };
      "host nixpkgs.overlays merge with purr's shared overlays" = {
        expr =
          let
            overlays = server.config.nixpkgs.overlays;
            anyFunction = builtins.foldl' (acc: o: acc || builtins.isFunction o) false overlays;
          in
          {
            length = builtins.length overlays;
            hasServerExtra = builtins.elem "server-extra-overlay" overlays;
            hasSharedCustom = anyFunction;
          };
        expected = {
          length = 2;
          hasServerExtra = true;
          hasSharedCustom = true;
        };
      };
      "host nixpkgs.config merges on top of purr's nixpkgsConfig" = {
        expr = server.config.nixpkgs.config;
        expected = {
          allowUnfree = true;
          permittedInsecurePackages = [ "host-extra" ];
        };
      };
      "module sees the defining flake's inputs" = {
        expr = server.config.demo.inputsRef.hasDefiningInputs;
        expected = true;
      };
      "darwin host evaluated" = {
        expr = {
          hostName = macbook.config.networking.hostName;
          stateVersion = macbook.config.system.stateVersion;
        };
        expected = {
          hostName = "macbook";
          stateVersion = "24.11";
        };
      };
    };
  };

  # ---- namespace bridge: system module -> linked home-manager user ----
  namespaceBridge = {
    tests = {
      "home-manager.users contains linked users" = {
        expr = attrNames (server.config."home-manager".users or { });
        expected = [
          "alice"
          "root"
        ];
      };
      "bridge config forwarded to alice" = {
        expr =
          let
            users = server.config."home-manager".users;
            bridge = builtins.filter (
              m:
              builtins.isAttrs m && m ? config && m.config ? home && m.config.home.packages or [ ] == [ "cowsay" ]
            ) (users.alice.imports or [ ]);
          in
          length bridge;
        expected = 1;
      };
      "linked home path imported for alice" = {
        expr =
          let
            users = server.config."home-manager".users;
            paths = builtins.filter (
              m: builtins.isPath m && lib.hasSuffix "alice@server/default.nix" (toString m)
            ) (users.alice.imports or [ ]);
          in
          length paths;
        expected = 1;
      };
      "root user receives empty bridge config (no homeConfig)" = {
        expr =
          let
            users = server.config."home-manager".users;
            bridgesWithContent = builtins.filter (m: builtins.isAttrs m && m ? config && m.config ? home) (
              users.root.imports or [ ]
            );
          in
          length bridgesWithContent;
        expected = 0;
      };
      "system-injected home exposes user arg and injects username" = {
        expr =
          let
            users = server.config."home-manager".users;
            shims = builtins.filter (m: builtins.isAttrs m && m ? _module) (users.alice.imports or [ ]);
            shim = builtins.head shims;
          in
          {
            user = shim._module.args.user;
            username = shim.home.username;
            homeDirectory = shim.home.homeDirectory;
          };
        expected = {
          user = "alice";
          username = lib.mkDefault "alice";
          homeDirectory = lib.mkDefault "/home/alice";
        };
      };
      "users.users auto-created for non-root homes only" = {
        expr = attrNames (server.config.users.users or { });
        expected = [ "alice" ];
      };
      "home-manager extraSpecialArgs carry purr metadata and merged lib" = {
        expr = {
          namespace = server.config."home-manager".extraSpecialArgs.namespace;
          host = server.config."home-manager".extraSpecialArgs.host;
          purrName = server.config."home-manager".extraSpecialArgs.purr.meta.name;
          # The bridge must NOT override home-manager's own `lib` — that breaks
          # home-manager's internal submodule evaluation (TODO: upstream home-manager
          # regression). Bridged homes keep home-manager's extended lib; the merged
          # namespace lib is exposed uniformly as `purr.lib`.
          noLibOverride = !(server.config."home-manager".extraSpecialArgs ? lib);
          hasPurrLib = (server.config."home-manager".extraSpecialArgs.purr.lib or { }) ? "demo";
          systemMetaName = server.config."home-manager".extraSpecialArgs.purr.systemMeta.name;
        };
        expected = {
          namespace = "demo";
          host = "server";
          purrName = "server";
          noLibOverride = true;
          hasPurrLib = true;
          systemMetaName = "server";
        };
      };
    };
  };

  # ---- homes: standalone homeConfigurations ----
  homes = {
    tests = {
      "discovers all homes" = {
        expr = sort (a: b: a < b) (attrNames (result.homeConfigurations or { }));
        expected = [
          "alice@macbook"
          "alice@server"
          "root@server"
        ];
      };
      "linux home auto-injects username and homeDirectory" = {
        expr = {
          username = result.homeConfigurations."alice@server".config.home.username;
          homeDirectory = result.homeConfigurations."alice@server".config.home.homeDirectory;
          stateVersion = result.homeConfigurations."alice@server".config.home.stateVersion;
        };
        expected = {
          username = "alice";
          homeDirectory = "/home/alice";
          stateVersion = "24.11";
        };
      };
      "darwin home auto-injects /Users homeDirectory" = {
        expr = result.homeConfigurations."alice@macbook".config.home.homeDirectory;
        expected = "/Users/alice";
      };
      "linux home extraSpecialArgs carry purr metadata" = {
        expr = {
          user = result.homeConfigurations."alice@server".extraSpecialArgs.purr.meta.user;
          host = result.homeConfigurations."alice@server".extraSpecialArgs.purr.meta.host;
          arch = result.homeConfigurations."alice@server".extraSpecialArgs.purr.meta.arch;
          namespace = result.homeConfigurations."alice@server".extraSpecialArgs.namespace;
          hasLib = (result.homeConfigurations."alice@server".extraSpecialArgs.lib or { }) ? "demo";
          hasPurrLib = (result.homeConfigurations."alice@server".extraSpecialArgs.purr.lib or { }) ? "demo";
        };
        expected = {
          user = "alice";
          host = "server";
          arch = "x86_64";
          namespace = "demo";
          hasLib = true;
          hasPurrLib = true;
        };
      };
      "linux home purr.systemMeta back-links to its system meta" = {
        expr = {
          name = result.homeConfigurations."alice@server".extraSpecialArgs.purr.systemMeta.name;
          tier = result.homeConfigurations."alice@server".extraSpecialArgs.purr.systemMeta.tier;
          deployable = result.homeConfigurations."alice@server".extraSpecialArgs.purr.systemMeta.deployable;
        };
        expected = {
          name = "server";
          tier = "prod";
          deployable = true;
        };
      };
      "linux home purr.systemMetas registers all hosts" = {
        expr = sort (a: b: a < b) (
          attrNames (result.homeConfigurations."alice@server".extraSpecialArgs.purr.systemMetas or { })
        );
        expected = [
          "iso"
          "macbook"
          "server"
        ];
      };
      "darwin home purr.systemMeta back-links to macbook" = {
        expr = result.homeConfigurations."alice@macbook".extraSpecialArgs.purr.systemMeta.name;
        expected = "macbook";
      };
      "standalone home has no purrLib arg" = {
        expr = result.homeConfigurations."alice@server".extraSpecialArgs ? purrLib;
        expected = false;
      };
      "home packages evaluated" = {
        expr = result.homeConfigurations."alice@server".config.home.packages;
        expected = [ "alice-pkg" ];
      };
    };
  };

  # ---- module outputs ----
  modules = {
    tests = {
      "nixosModules contains discovered + bundled default" = {
        expr = sort (a: b: a < b) (attrNames (result.nixosModules or { }));
        expected = [
          "base"
          "common"
          "default"
          "inputs-ref"
          "services"
        ];
      };
      "darwinModules merges shared" = {
        expr = attrNames (result.darwinModules or { });
        expected = [
          "common"
          "default"
          "inputs-ref"
        ];
      };
      "homeModules contains git + bundled default" = {
        expr = attrNames (result.homeModules or { });
        expected = [
          "default"
          "git"
        ];
      };
      "nixosModules.default bundles all modules" = {
        expr =
          let
            dflt = result.nixosModules.default or { };
          in
          (dflt ? imports) && (length dflt.imports or 0) == 4;
        expected = true;
      };
      "discovered module evaluates with namespace lib" = {
        expr =
          let
            eval = lib.evalModules {
              modules = [
                moduleShim
                result.nixosModules.default
              ];
              specialArgs = {
                pkgs = { };
              };
            };
          in
          eval.config.demo.base.greeting;
        expected = "HI";
      };
      "discovered module honors mkEnableOption" = {
        expr =
          let
            eval = lib.evalModules {
              modules = [
                moduleShim
                result.nixosModules.default
                {
                  config.demo.services.openssh.enable = true;
                }
              ];
              specialArgs = {
                pkgs = { };
              };
            };
          in
          eval.config.services.openssh.enable;
        expected = true;
      };
    };
  };

  # ---- auto-discovered per-system outputs ----
  autoOutputs = {
    tests = {
      "packages discovers regular + by-name" = {
        expr = sort (a: b: a < b) (attrNames (result.packages."x86_64-linux" or { }));
        expected = [
          "cowsay"
          "hello"
        ];
      };
      "package module receives namespace, pkgs, lib" = {
        expr = {
          namespace = result.packages."x86_64-linux".hello.namespace;
          system = result.packages."x86_64-linux".hello.system;
          libHasNs = result.packages."x86_64-linux".hello.libHasNs;
          upper = result.packages."x86_64-linux".hello.upper;
        };
        expected = {
          namespace = "demo";
          system = "x86_64-linux";
          libHasNs = true;
          upper = "ABC";
        };
      };
      "by-name package discovered" = {
        expr = {
          byName = result.packages."x86_64-linux".cowsay.byName or false;
          system = result.packages."x86_64-linux".cowsay.system;
        };
        expected = {
          byName = true;
          system = "x86_64-linux";
        };
      };
      "checks discovered" = {
        expr = result.checks."x86_64-linux".lint;
        expected = "check-x86_64-linux";
      };
      "devShells discovered" = {
        expr = result.devShells."x86_64-linux".dev._type;
        expected = "mkShell";
      };
      "apps discovered" = {
        expr = result.apps."x86_64-linux".run.program;
        expected = "hello-drv-x86_64-linux/bin/hello";
      };
      "overlays discovered and callable" = {
        expr =
          let
            overlay = result.overlays.custom;
            final = {
              hello = "final-hello";
            };
          in
          (overlay final { }).custom;
        expected = "final-hello";
      };
      "templates discovered" = {
        expr = result.templates.rust.description;
        expected = "rust template via purr";
      };
      "formatter discovered per system" = {
        expr = result.formatter."x86_64-linux";
        expected = "hello-drv-x86_64-linux";
      };
      "legacyPackages discovered" = {
        expr = result.legacyPackages."x86_64-linux".old;
        expected = "legacy-x86_64-linux";
      };
    };
  };

  # ---- custom lib namespace ----
  libNamespace = {
    tests = {
      "lib.demo exposes root marker" = {
        expr = result.lib.demo.rootMarker;
        expected = "root:demo";
      };
      "lib.demo exposes nested lib functions" = {
        expr = result.lib.demo.math.add 2 3;
        expected = 5;
      };
      "lib.demo exposes deeply nested lib functions" = {
        expr = result.lib.demo.strings.upper.upper "nix";
        expected = "NIX";
      };
    };
  };

  # ---- image-only hosts and images output ----
  imageHosts = {
    tests = {
      "image-only host excluded from nixosConfigurations" = {
        expr = result.nixosConfigurations ? "iso";
        expected = false;
      };
      "image-only host present in images output" = {
        expr = result.images.iso or { };
        expected = {
          iso = "iso-drv";
        };
      };
    };
  };

  # ---- host meta (hosts.<name>.meta config) ----
  hostMeta = {
    tests = {
      "hosts meta config flows into server purr.meta" = {
        expr = {
          tier = server.specialArgs.purr.meta.tier;
          region = server.specialArgs.purr.meta.region;
          images = server.specialArgs.purr.meta.images;
          deployable = server.specialArgs.purr.meta.deployable;
        };
        expected = {
          tier = "prod";
          region = "us-east";
          images = [ ];
          deployable = true;
        };
      };
      "iso host meta.nix function evaluates and drives images output" = {
        expr = {
          image = result.images.iso.iso;
          hydraImage = result.hydraJobs.images.iso.iso;
        };
        expected = {
          image = "iso-drv";
          hydraImage = "iso-drv";
        };
      };
    };
  };

  # ---- outputsBuilder pivots per-system outputs ----
  outputsBuilder = {
    tests = {
      "custom per-system output pivoted to attrset" = {
        expr = attrNames (result.customPerSystem or { });
        expected = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
      };
      "custom output value correct per system" = {
        expr = result.customPerSystem."x86_64-linux";
        expected = "custom-x86_64-linux";
      };
    };
  };

  # ---- hydraJobs ----
  hydraJobs = {
    tests = {
      "directory jobs discovered" = {
        expr = result.hydraJobs.build."x86_64-linux".hello;
        expected = "job-x86_64-linux";
      };
      "mirrored checks included" = {
        expr = result.hydraJobs.checks."x86_64-linux".lint;
        expected = "check-x86_64-linux";
      };
      "mirrored packages included" = {
        expr = result.hydraJobs.packages."x86_64-linux".hello._type;
        expected = "package";
      };
      "mirrored nixosConfigurations included" = {
        expr = result.hydraJobs.nixosConfigurations."x86_64-linux".server;
        expected = "toplevel-server";
      };
      "mirrored homeConfigurations included" = {
        expr = result.hydraJobs.homeConfigurations."x86_64-linux"."alice@server";
        expected = "activation-alice";
      };
      "image jobs included in hydraJobs" = {
        expr = result.hydraJobs.images.iso or { };
        expected = {
          iso = "iso-drv";
        };
      };
      "image-only host not mirrored as nixosConfigurations" = {
        expr = result.hydraJobs.nixosConfigurations."x86_64-linux" ? "iso";
        expected = false;
      };
    };
  };

  # ---- hydraJobs.as ----
  hydraJobsAs = {
    tests = {
      "renamed output present, hydraJobs absent" = {
        expr = {
          hasBuilds = renamed ? "builds";
          hasHydraJobs = renamed ? "hydraJobs";
        };
        expected = {
          hasBuilds = true;
          hasHydraJobs = false;
        };
      };
      "renamed output carries the jobs" = {
        expr = renamed.builds.nixosConfigurations."x86_64-linux".server;
        expected = "toplevel-server";
      };
    };
  };
}
