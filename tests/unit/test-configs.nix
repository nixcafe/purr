# Unit tests for lib/configs.nix — system and home config builders.
{ lib }:
let
  confs = import ../../lib/configs.nix {
    inherit lib;
  };

  inherit (confs)
    buildHomeConfigs
    buildSystemConfigs
    findMatchingHomes
    formatOutputKey
    imagesFromConfigs
    parseArchFormat
    parseUserHost
    ;

  homeFixture = ./fixtures/home/default.nix;
  sysLinuxFixture = ./fixtures/system-linux/default.nix;
  sysImageFixture = ./fixtures/system-image/default.nix;
  sysImageDeployableFixture = ./fixtures/system-image-deployable/default.nix;
  sysDarwinFixture = ./fixtures/system-darwin/default.nix;
  sysMetaFunctionFixture = ./fixtures/system-meta-function/default.nix;
  sysMetaReservedFixture = ./fixtures/system-meta-reserved/default.nix;
  sysMetaMergeFixture = ./fixtures/system-meta-merge/default.nix;
  sysMetaNotAttrsFixture = ./fixtures/system-meta-not-attrs/default.nix;

  homeManagerInput = {
    lib.homeManagerConfiguration = args: {
      inherit (args) extraSpecialArgs modules;
    };
  };

  nixosInputs = {
    nixpkgs.lib.nixosSystem =
      {
        modules,
        system,
        specialArgs,
      }:
      {
        inherit modules specialArgs system;
      };
  };

  nixosWithHmInputs = nixosInputs // {
    home-manager = {
      darwinModules.home-manager = "hm-darwin";
      nixosModules.home-manager = "hm-mod";
    };
  };

  darwinInputs = {
    nixpkgs.lib = { };
    nix-darwin.lib.darwinSystem =
      {
        modules,
        system,
        specialArgs,
      }:
      {
        inherit modules specialArgs system;
      };
  };

  darwinWithHmInputs = darwinInputs // {
    home-manager = {
      darwinModules.home-manager = "hm-darwin";
      nixosModules.home-manager = "hm-mod";
    };
  };

  sortByUser = builtins.sort (a: b: a.user < b.user);
in
{
  # ---- parseArchFormat ----
  parseArchFormat = {
    tests = {
      "parses x86_64-linux" = {
        expr = parseArchFormat "x86_64-linux";
        expected = {
          arch = "x86_64";
          format = "linux";
        };
      };
      "parses aarch64-darwin" = {
        expr = parseArchFormat "aarch64-darwin";
        expected = {
          arch = "aarch64";
          format = "darwin";
        };
      };
      "parses x86_64-iso" = {
        expr = parseArchFormat "x86_64-iso";
        expected = {
          arch = "x86_64";
          format = "iso";
        };
      };
      "malformed archFormat yields nulls" = {
        expr = parseArchFormat "x86_64";
        expected = {
          arch = null;
          format = null;
        };
      };
    };
  };

  # ---- parseUserHost ----
  parseUserHost = {
    tests = {
      "parses alice@server" = {
        expr = parseUserHost "alice@server";
        expected = {
          user = "alice";
          host = "server";
        };
      };
      "parses root@host" = {
        expr = parseUserHost "root@host";
        expected = {
          user = "root";
          host = "host";
        };
      };
      "malformed userHost yields nulls" = {
        expr = parseUserHost "alice";
        expected = {
          user = null;
          host = null;
        };
      };
    };
  };

  # ---- formatOutputKey ----
  formatOutputKey = {
    tests = {
      "linux maps to nixosConfigurations" = {
        expr = formatOutputKey "linux";
        expected = "nixosConfigurations";
      };
      "darwin maps to darwinConfigurations" = {
        expr = formatOutputKey "darwin";
        expected = "darwinConfigurations";
      };
      "unsupported format throws" = {
        expr = (builtins.tryEval (formatOutputKey "iso")).success;
        expected = false;
      };
    };
  };

  # ---- findMatchingHomes ----
  findMatchingHomes = {
    tests = {
      "finds matching homes across all architectures" = {
        expr =
          let
            homes = {
              "x86_64-linux" = {
                "alice@myhost" = homeFixture;
                "bob@other" = homeFixture;
              };
              "aarch64-linux" = {
                "charlie@myhost" = homeFixture;
              };
            };
          in
          sortByUser (findMatchingHomes homes "myhost");
        expected = [
          {
            user = "alice";
            path = homeFixture;
          }
          {
            user = "charlie";
            path = homeFixture;
          }
        ];
      };
      "no matching homes yields empty list" = {
        expr = findMatchingHomes {
          "x86_64-linux"."alice@other" = homeFixture;
        } "myhost";
        expected = [ ];
      };
      "empty discoveredHomes yields empty list" = {
        expr = findMatchingHomes { } "myhost";
        expected = [ ];
      };
    };
  };

  # ---- imagesFromConfigs ----
  imagesFromConfigs = {
    tests = {
      "extracts declared image formats from imageRecipes" = {
        expr = imagesFromConfigs {
          host = {
            cfg = {
              config.system.build.images.iso = "iso-drv";
            };
            images = [ "iso" ];
            system = "x86_64-linux";
          };
        } null;
        expected = {
          host = {
            iso = "iso-drv";
          };
        };
      };
      "structure is lazy: enumerating names does not force the config" = {
        expr =
          let
            result = imagesFromConfigs {
              host = {
                cfg = {
                  config.system.build.images.iso = "iso-drv";
                };
                images = [
                  "iso"
                  "qemu"
                ];
                system = "x86_64-linux";
              };
            } null;
          in
          {
            names = builtins.attrNames result.host;
            iso = result.host.iso;
          };
        expected = {
          names = [
            "iso"
            "qemu"
          ];
          iso = "iso-drv";
        };
      };
      "declared format missing from config throws on force" = {
        expr =
          let
            result = imagesFromConfigs {
              host = {
                cfg = {
                  config.system.build.images.iso = "iso-drv";
                };
                images = [ "qemu" ];
                system = "x86_64-linux";
              };
            } null;
          in
          builtins.tryEval result.host.qemu;
        expected = {
          success = false;
          value = false;
        };
      };
      "skips hosts with no declared images" = {
        expr = imagesFromConfigs {
          host = {
            cfg = { };
            images = [ ];
            system = "x86_64-linux";
          };
        } null;
        expected = { };
      };
      "filters imageRecipes by system" = {
        expr =
          let
            recipes = {
              x86 = {
                cfg = {
                  config.system.build.images.iso = "iso-x86";
                };
                images = [ "iso" ];
                system = "x86_64-linux";
              };
              arm = {
                cfg = {
                  config.system.build.images.iso = "iso-arm";
                };
                images = [ "iso" ];
                system = "aarch64-linux";
              };
            };
            filtered = imagesFromConfigs recipes [ "x86_64-linux" ];
          in
          {
            hasX86 = filtered ? x86;
            hasArm = filtered ? arm;
            iso = filtered.x86.iso;
          };
        expected = {
          hasX86 = true;
          hasArm = false;
          iso = "iso-x86";
        };
      };
      "empty imageRecipes yields empty attrset" = {
        expr = imagesFromConfigs { } null;
        expected = { };
      };
    };
  };

  # ---- buildHomeConfigs ----
  buildHomeConfigs = {
    tests = {
      "returns empty when no home-manager input" = {
        expr = buildHomeConfigs {
          discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
          inputs = { };
        };
        expected = { };
      };
      "returns empty when no homes are discovered" = {
        expr = buildHomeConfigs {
          discoveredHomes = { };
          inputs.home-manager = homeManagerInput;
        };
        expected = { };
      };
      "keys the result by user@host" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
            };
          in
          {
            hasAlice = result ? "alice@myhost";
            key = builtins.head (builtins.attrNames result);
          };
        expected = {
          hasAlice = true;
          key = "alice@myhost";
        };
      };
      "injects purr metadata into extraSpecialArgs" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
            };
            purr = result."alice@myhost".extraSpecialArgs.purr;
          in
          {
            fields = builtins.removeAttrs purr [ "lib" ];
            hasLib = purr ? lib;
            libHasAttrNames = purr.lib ? attrNames;
          };
        expected = {
          fields = {
            meta = {
              arch = "x86_64";
              archFormat = "x86_64-linux";
              format = "linux";
              host = "myhost";
              isDarwin = false;
              isLinux = true;
              system = "x86_64-linux";
              user = "alice";
            };
            systemMeta = null;
            systemMetas = { };
          };
          hasLib = true;
          libHasAttrNames = true;
        };
      };
      "carries namespace system inputs and merged lib in extraSpecialArgs" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
              namespace = "my-ns";
            };
            args = result."alice@myhost".extraSpecialArgs;
          in
          {
            inherit (args) namespace;
            inherit (args) system;
            hasInputs = args ? inputs;
            hasLib = args ? lib;
            libMarker = args.lib ? attrNames;
            noPurrLib = !(args ? purrLib);
          };
        expected = {
          namespace = "my-ns";
          system = "x86_64-linux";
          hasInputs = true;
          hasLib = true;
          libMarker = true;
          noPurrLib = true;
        };
      };
      "auto-injects home.username and homeDirectory on linux" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
            };
            inject = builtins.head result."alice@myhost".modules;
          in
          {
            username = inject.home.username.content;
            homeDirectory = inject.home.homeDirectory.content;
          };
        expected = {
          username = "alice";
          homeDirectory = "/home/alice";
        };
      };
      "auto-injects darwin homeDirectory" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes = {
                "aarch64-darwin"."alice@macbook" = homeFixture;
                "x86_64-linux"."alice@myhost" = homeFixture;
              };
              inputs.home-manager = homeManagerInput;
            };
            darwin = builtins.head result."alice@macbook".modules;
            linux = builtins.head result."alice@myhost".modules;
          in
          {
            darwinHomeDirectory = darwin.home.homeDirectory.content;
            linuxHomeDirectory = linux.home.homeDirectory.content;
          };
        expected = {
          darwinHomeDirectory = "/Users/alice";
          linuxHomeDirectory = "/home/alice";
        };
      };
      "autoInject false omits the injection module" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
              autoInject = false;
            };
            modules = result."alice@myhost".modules;
          in
          {
            count = builtins.length modules;
            first = builtins.head modules;
          };
        expected = {
          count = 1;
          first = homeFixture;
        };
      };
      "merges extraModules.home into modules" = {
        expr =
          let
            extraMod = {
              home.extra = true;
            };
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
              extraModules.home = [ extraMod ];
            };
          in
          builtins.elem extraMod result."alice@myhost".modules;
        expected = true;
      };
      "accepts homeManager as alias input" = {
        expr =
          let
            inputs = {
              homeManager = homeManagerInput;
              nixpkgs = { };
            };
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inherit inputs;
            };
          in
          {
            hasAlice = result ? "alice@myhost";
            user = result."alice@myhost".extraSpecialArgs.purr.meta.user;
          };
        expected = {
          hasAlice = true;
          user = "alice";
        };
      };
      "purr.systemMeta back-links to the matching system meta" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              inputs.home-manager = homeManagerInput;
            };
          in
          result."alice@myhost".extraSpecialArgs.purr.systemMeta;
        expected = {
          arch = "x86_64";
          archFormat = "x86_64-linux";
          deployable = true;
          format = "linux";
          homes = [
            {
              user = "alice";
              host = "myhost";
            }
          ];
          images = [ ];
          isDarwin = false;
          isLinux = true;
          name = "myhost";
          host = "myhost";
          system = "x86_64-linux";
        };
      };
      "purr.systemMeta is null without a matching system" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@somewhere" = homeFixture;
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              inputs.home-manager = homeManagerInput;
            };
          in
          result."alice@somewhere".extraSpecialArgs.purr.systemMeta;
        expected = null;
      };
      "purr.systemMetas carries the registry into homes" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              discoveredSystems."x86_64-linux" = {
                myhost = sysLinuxFixture;
                other = sysLinuxFixture;
              };
              inputs.home-manager = homeManagerInput;
            };
            purr = result."alice@myhost".extraSpecialArgs.purr;
          in
          {
            keys = builtins.attrNames purr.systemMetas;
            self = purr.systemMetas.myhost.name;
            other = purr.systemMetas.other.name;
          };
        expected = {
          keys = [
            "myhost"
            "other"
          ];
          self = "myhost";
          other = "other";
        };
      };
    };
  };

  # ---- buildSystemConfigs ----
  buildSystemConfigs = {
    tests = {
      "exposes linux hosts under nixosConfigurations" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
          in
          {
            outputKeys = builtins.attrNames result;
            hostSystem = result.nixosConfigurations.myhost.system;
          };
        expected = {
          outputKeys = [
            "configSystems"
            "imageRecipes"
            "nixosConfigurations"
          ];
          hostSystem = "x86_64-linux";
        };
      };
      "exposes darwin hosts under darwinConfigurations" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inputs = darwinInputs;
            };
          in
          {
            outputKeys = builtins.attrNames result;
            hostSystem = result.darwinConfigurations.mac1.system;
          };
        expected = {
          outputKeys = [
            "configSystems"
            "darwinConfigurations"
            "imageRecipes"
          ];
          hostSystem = "aarch64-darwin";
        };
      };
      "accepts darwin as alias input for nix-darwin" = {
        expr =
          let
            inputs = {
              darwin.lib.darwinSystem =
                {
                  modules,
                  system,
                  specialArgs,
                }:
                {
                  inherit modules specialArgs system;
                };
              nixpkgs.lib = { };
            };
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inherit inputs;
            };
          in
          result ? darwinConfigurations;
        expected = true;
      };
      "passes purr metadata to linux specialArgs" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
          in
          result.nixosConfigurations.myhost.specialArgs.purr;
        expected = {
          meta = {
            arch = "x86_64";
            archFormat = "x86_64-linux";
            deployable = true;
            format = "linux";
            homes = [ ];
            images = [ ];
            isDarwin = false;
            isLinux = true;
            name = "myhost";
            host = "myhost";
            system = "x86_64-linux";
          };
          systemMetas = {
            myhost = {
              arch = "x86_64";
              archFormat = "x86_64-linux";
              deployable = true;
              format = "linux";
              homes = [ ];
              images = [ ];
              isDarwin = false;
              isLinux = true;
              name = "myhost";
              host = "myhost";
              system = "x86_64-linux";
            };
          };
        };
      };
      "passes purr metadata to darwin specialArgs" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inputs = darwinInputs;
            };
          in
          result.darwinConfigurations.mac1.specialArgs.purr;
        expected = {
          meta = {
            arch = "aarch64";
            archFormat = "aarch64-darwin";
            deployable = true;
            format = "darwin";
            homes = [ ];
            images = [ ];
            isDarwin = true;
            isLinux = false;
            name = "mac1";
            host = "mac1";
            system = "aarch64-darwin";
          };
          systemMetas = {
            mac1 = {
              arch = "aarch64";
              archFormat = "aarch64-darwin";
              deployable = true;
              format = "darwin";
              homes = [ ];
              images = [ ];
              isDarwin = true;
              isLinux = false;
              name = "mac1";
              host = "mac1";
              system = "aarch64-darwin";
            };
          };
        };
      };
      "purr.systemMetas registers all discovered hosts and includes self" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux" = {
                  myhost = sysLinuxFixture;
                  other = sysLinuxFixture;
                };
                "aarch64-darwin".mac1 = sysDarwinFixture;
              };
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            registry = result.nixosConfigurations.myhost.specialArgs.purr.systemMetas;
          in
          {
            keys = builtins.attrNames registry;
            self = registry.myhost.name;
            other = registry.other.name;
            darwin = registry.mac1.name;
            hasNoValue = !(registry ? myhost.value) && !(registry ? myhost.cfg);
          };
        expected = {
          keys = [
            "mac1"
            "myhost"
            "other"
          ];
          self = "myhost";
          other = "other";
          darwin = "mac1";
          hasNoValue = true;
        };
      };
      "passes system host namespace and inputs to specialArgs" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              namespace = "my-ns";
            };
            spec = result.nixosConfigurations.myhost.specialArgs;
          in
          {
            inherit (spec) host;
            inherit (spec) namespace;
            inherit (spec) system;
            hasInputs = spec ? inputs;
            hasLib = spec ? lib;
          };
        expected = {
          host = "myhost";
          namespace = "my-ns";
          system = "x86_64-linux";
          hasInputs = true;
          hasLib = true;
        };
      };
      "auto-injects networking.hostName" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            firstModule = builtins.head result.nixosConfigurations.myhost.modules;
          in
          firstModule.networking.hostName.content;
        expected = "myhost";
      };
      "autoInject false skips hostName injection" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              autoInject = false;
            };
            modules = result.nixosConfigurations.myhost.modules;
          in
          {
            noHostNameModule = builtins.filter (m: builtins.isAttrs m && m ? networking) modules == [ ];
            metaInjected = result.nixosConfigurations.myhost.specialArgs.purr.meta.images == [ ];
          };
        expected = {
          noHostNameModule = true;
          metaInjected = true;
        };
      };
      "injects nixpkgsConfig as a default-priority nixpkgs.config module" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              nixpkgsConfig = {
                allowUnfree = true;
                permittedInsecurePackages = [ "bad-1.0" ];
              };
            };
            modules = result.nixosConfigurations.myhost.modules;
            nixpkgsMod = builtins.head (builtins.filter (m: builtins.isAttrs m && m ? nixpkgs) modules);
          in
          {
            config = nixpkgsMod.nixpkgs.config;
            overlays = nixpkgsMod.nixpkgs.overlays;
            configWrapped = nixpkgsMod.nixpkgs.config._type or null;
            overlaysWrapped = nixpkgsMod.nixpkgs.overlays._type or null;
          };
        expected = {
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [ "bad-1.0" ];
          };
          overlays = [ ];
          configWrapped = null;
          overlaysWrapped = null;
        };
      };
      "injects sharedOverlays as a default-priority nixpkgs.overlays module" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              sharedOverlays = [
                "overlay1"
                "overlay2"
              ];
            };
            modules = result.nixosConfigurations.myhost.modules;
            nixpkgsMod = builtins.head (builtins.filter (m: builtins.isAttrs m && m ? nixpkgs) modules);
          in
          nixpkgsMod.nixpkgs.overlays;
        expected = [
          "overlay1"
          "overlay2"
        ];
      };
      "injects extraModules.nixos into linux configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              extraModules.nixos = [ extraMod ];
            };
          in
          builtins.elem extraMod result.nixosConfigurations.myhost.modules;
        expected = true;
      };
      "does not inject darwin extras into linux configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              extraModules.darwin = [ extraMod ];
            };
          in
          builtins.elem extraMod result.nixosConfigurations.myhost.modules;
        expected = false;
      };
      "injects extraModules.darwin into darwin configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inputs = darwinInputs;
              extraModules.darwin = [ extraMod ];
            };
          in
          builtins.elem extraMod result.darwinConfigurations.mac1.modules;
        expected = true;
      };
      "exposes image hosts in imageRecipes and excludes image-only hosts" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux" = {
                isobuilder = sysImageFixture;
                isodeploy = sysImageDeployableFixture;
                myhost = sysLinuxFixture;
              };
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            recipe = result.imageRecipes.isobuilder;
          in
          {
            hasIsoBuilder = result.nixosConfigurations ? isobuilder;
            hasIsoDeploy = result.nixosConfigurations ? isodeploy;
            hasMyhost = result.nixosConfigurations ? myhost;
            imageHosts = builtins.attrNames result.imageRecipes;
            recipeSystem = recipe.system;
            recipeImages = recipe.images;
            recipeCfgIsAttrs = builtins.isAttrs recipe.cfg;
            recipeCfgSystem = recipe.cfg.system;
          };
        expected = {
          hasIsoBuilder = false;
          hasIsoDeploy = true;
          hasMyhost = true;
          imageHosts = [
            "isobuilder"
            "isodeploy"
          ];
          recipeSystem = "x86_64-linux";
          recipeImages = [ "iso" ];
          recipeCfgIsAttrs = true;
          recipeCfgSystem = "x86_64-linux";
        };
      };
      "empty discoveredSystems yields only metadata keys" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems = { };
              discoveredHomes = { };
              inputs = nixosInputs;
            };
          in
          {
            outputKeys = builtins.attrNames result;
            inherit (result) imageRecipes;
          };
        expected = {
          outputKeys = [
            "configSystems"
            "imageRecipes"
          ];
          imageRecipes = { };
        };
      };
      "auto-creates users.users for non-root linked homes" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes."x86_64-linux" = {
                "alice@myhost" = homeFixture;
                "bob@myhost" = homeFixture;
              };
              inputs = nixosWithHmInputs;
            };
            modules = result.nixosConfigurations.myhost.modules;
            userMods = builtins.filter (m: builtins.isAttrs m && m ? users) modules;
          in
          builtins.attrNames (builtins.head userMods).users.users;
        expected = [
          "alice"
          "bob"
        ];
      };
      "excludes root from users.users auto-creation" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes."x86_64-linux"."root@myhost" = homeFixture;
              inputs = nixosWithHmInputs;
            };
            modules = result.nixosConfigurations.myhost.modules;
            userMods = builtins.filter (m: builtins.isAttrs m && m ? users) modules;
          in
          userMods == [ ];
        expected = true;
      };
      "does not auto-create users.users for darwin homes" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes."aarch64-darwin"."alice@mac1" = homeFixture;
              inputs = darwinWithHmInputs;
            };
            modules = result.darwinConfigurations.mac1.modules;
            userMods = builtins.filter (m: builtins.isAttrs m && m ? users) modules;
          in
          userMods == [ ];
        expected = true;
      };
      "purr.homes lists linked homes" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = homeFixture;
                "aarch64-linux"."bob@myhost" = homeFixture;
              };
              inputs = nixosWithHmInputs;
            };
          in
          sortByUser result.nixosConfigurations.myhost.specialArgs.purr.meta.homes;
        expected = [
          {
            host = "myhost";
            user = "alice";
          }
          {
            host = "myhost";
            user = "bob";
          }
        ];
      };
      "wires the home-manager bridge module" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs = nixosWithHmInputs;
            };
            modules = result.nixosConfigurations.myhost.modules;
            wrapper = builtins.head (builtins.filter (m: builtins.isFunction m) modules);
            linked = wrapper {
              config = {
                purr.users.alice.homeConfig = {
                  home.packages = [ "cowsay" ];
                };
              };
              inherit lib;
            };
          in
          linked."home-manager".users.alice.imports;
        expected = [
          {
            config = {
              home.packages = [ "cowsay" ];
            };
          }
          {
            _module.args.user = "alice";
            home.username = lib.mkDefault "alice";
            home.homeDirectory = lib.mkDefault "/home/alice";
          }
          homeFixture
        ];
      };
    };
  };

  # ---- host meta (meta.nix / hostsMeta config) ----
  hostMeta = {
    tests = {
      "meta.nix images and custom keys flow into purr.meta and imageRecipes" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysImageFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            meta = result.imageRecipes.myhost.cfg.specialArgs.purr.meta;
            recipe = result.imageRecipes.myhost;
          in
          {
            inherit (meta)
              arch
              deployable
              format
              images
              isLinux
              name
              system
              ;
            cfgImages = recipe.images;
          };
        expected = {
          images = [ "iso" ];
          deployable = false;
          name = "myhost";
          arch = "x86_64";
          format = "linux";
          system = "x86_64-linux";
          isLinux = true;
          cfgImages = [ "iso" ];
        };
      };
      "meta.nix function receives inputs and structural args" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysMetaFunctionFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            meta = result.imageRecipes.myhost.cfg.specialArgs.purr.meta;
          in
          {
            inherit (meta) images tier;
            isDeployable = result ? nixosConfigurations;
          };
        expected = {
          images = [ "iso" ];
          tier = "from-function-x86_64";
          isDeployable = false;
        };
      };
      "hostsMeta deep-merges over meta.nix" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysMetaMergeFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              hostsMeta.myhost = {
                labels = {
                  env = "prod";
                  extra = true;
                };
              };
            };
            meta = result.imageRecipes.myhost.cfg.specialArgs.purr.meta;
          in
          {
            inherit (meta) images;
            labelsEnv = meta.labels.env;
            labelsTeam = meta.labels.team;
            labelsExtra = meta.labels.extra;
          };
        expected = {
          images = [ "iso" ];
          labelsEnv = "prod";
          labelsTeam = "core";
          labelsExtra = true;
        };
      };
      "hostsMeta leaf overrides meta.nix" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysMetaMergeFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              hostsMeta.myhost.images = [ "qemu" ];
            };
            meta = result.imageRecipes.myhost.cfg.specialArgs.purr.meta;
          in
          meta.images;
        expected = [ "qemu" ];
      };
      "reserved meta keys are dropped and auto value kept" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysMetaReservedFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
            meta = result.imageRecipes.myhost.cfg.specialArgs.purr.meta;
          in
          {
            inherit (meta)
              arch
              images
              name
              system
              ;
          };
        expected = {
          name = "myhost";
          arch = "x86_64";
          system = "x86_64-linux";
          images = [ "iso" ];
        };
      };
      "reserved keys in hostsMeta are dropped too" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              hostsMeta.myhost.name = "evil";
            };
            meta = result.nixosConfigurations.myhost.specialArgs.purr.meta;
          in
          meta.name;
        expected = "myhost";
      };
      "non-list images in meta throws" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              hostsMeta.myhost.images = "iso";
            };
          in
          (builtins.tryEval result.imageRecipes).success;
        expected = false;
      };
      "meta.nix returning a non-attrset throws" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysMetaNotAttrsFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
            };
          in
          (builtins.tryEval result.imageRecipes).success;
        expected = false;
      };
      "hostsMeta referencing unknown host throws" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              hostsMeta.ghost = { };
            };
          in
          (builtins.tryEval result.nixosConfigurations).success;
        expected = false;
      };
      "darwin images are ignored in imageRecipes" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inputs = darwinInputs;
              hostsMeta.mac1.images = [ "iso" ];
            };
          in
          builtins.attrNames result.imageRecipes;
        expected = [ ];
      };
      "deployable derived from images only when unset" = {
        expr =
          let
            base =
              extraConfig:
              {
                discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
                discoveredHomes = { };
                inputs = nixosInputs;
              }
              // extraConfig;
            withImages = buildSystemConfigs (base {
              hostsMeta.myhost.images = [ "iso" ];
            });
            withImagesDeployable = buildSystemConfigs (base {
              hostsMeta.myhost = {
                images = [ "iso" ];
                deployable = true;
              };
            });
          in
          {
            imageOnlyNotDeployable = withImages ? nixosConfigurations;
            explicitDeployable = withImagesDeployable.nixosConfigurations ? myhost;
            inImageRecipes = withImagesDeployable.imageRecipes ? myhost;
          };
        expected = {
          imageOnlyNotDeployable = false;
          explicitDeployable = true;
          inImageRecipes = true;
        };
      };
      "purr.meta is injected into darwin specialArgs too" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."aarch64-darwin".mac1 = sysDarwinFixture;
              discoveredHomes = { };
              inputs = darwinInputs;
              hostsMeta.mac1.customKey = "darwin-value";
            };
            meta = result.darwinConfigurations.mac1.specialArgs.purr.meta;
          in
          {
            inherit (meta) customKey deployable name;
          };
        expected = {
          name = "mac1";
          customKey = "darwin-value";
          deployable = true;
        };
      };
    };
  };

  # ---- extraArgs ----
  extraArgs = {
    tests = {
      "buildSystemConfigs passes extraArgs into specialArgs" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              extraArgs.myCustom = "system-extra";
            };
          in
          result.nixosConfigurations.myhost.specialArgs.myCustom;
        expected = "system-extra";
      };
      "buildSystemConfigs extraArgs does not override purr keys" = {
        expr =
          let
            result = buildSystemConfigs {
              discoveredSystems."x86_64-linux".myhost = sysLinuxFixture;
              discoveredHomes = { };
              inputs = nixosInputs;
              namespace = "my-ns";
              extraArgs.namespace = "bad-ns";
            };
            spec = result.nixosConfigurations.myhost.specialArgs;
          in
          {
            inherit (spec) namespace;
            inherit (spec) host;
            purrName = spec.purr.meta.name;
          };
        expected = {
          namespace = "my-ns";
          host = "myhost";
          purrName = "myhost";
        };
      };
      "buildHomeConfigs passes extraArgs into extraSpecialArgs" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
              extraArgs.myHomeExtra = "home-extra";
            };
          in
          result."alice@myhost".extraSpecialArgs.myHomeExtra;
        expected = "home-extra";
      };
      "buildHomeConfigs extraArgs does not override purr keys" = {
        expr =
          let
            result = buildHomeConfigs {
              discoveredHomes."x86_64-linux"."alice@myhost" = homeFixture;
              inputs.home-manager = homeManagerInput;
              namespace = "my-ns";
              extraArgs.namespace = "bad-ns";
            };
            args = result."alice@myhost".extraSpecialArgs;
          in
          {
            inherit (args) namespace;
            user = args.purr.meta.user;
            host = args.purr.meta.host;
          };
        expected = {
          namespace = "my-ns";
          user = "alice";
          host = "myhost";
        };
      };
    };
  };
}
