# Tests for lib/configs.nix
{ lib }:
let
  inherit (lib) elem;

  confs = import ../lib/configs.nix {
    inherit lib;
  };

  inherit (confs)
    buildHomeConfigs
    buildSystemConfigs
    findMatchingHomes
    formatOutputKey
    parseArchFormat
    parseUserHost
    ;
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
      "malformed name returns nulls" = {
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
      "malformed name returns nulls" = {
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
      "throws for unsupported format" = {
        expr = (builtins.tryEval (formatOutputKey "iso")).success;
        expected = false;
      };
    };
  };

  # ---- findMatchingHomes ----
  findMatchingHomes = {
    tests = {
      "finds matching homes across all archs" = {
        expr =
          let
            homes = {
              "x86_64-linux" = {
                "alice@myhost" = /tmp;
                "bob@other" = /tmp;
              };
              "aarch64-linux" = {
                "charlie@myhost" = /tmp;
              };
            };
            matches = findMatchingHomes homes "myhost";
          in
          builtins.sort (a: b: a.user < b.user) matches;
        expected = [
          {
            user = "alice";
            path = /tmp;
          }
          {
            user = "charlie";
            path = /tmp;
          }
        ];
      };
      "returns empty when no homes match" = {
        expr = findMatchingHomes { } "unknown";
        expected = [ ];
      };
    };
  };

  # ---- buildHomeConfigs ----
  buildHomeConfigs = {
    tests = {
      "returns empty when no home-manager input" = {
        expr = buildHomeConfigs {
          discoveredHomes = {
            "x86_64-linux"._ = null;
          };
          inputs = { };
          nixpkgsConfig = { };
        };
        expected = { };
      };
      "returns empty when no homes discovered" = {
        expr = buildHomeConfigs {
          discoveredHomes = { };
          inputs = { };
          nixpkgsConfig = { };
        };
        expected = { };
      };
      "injects purr metadata via extraSpecialArgs" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    extraSpecialArgs ? { },
                    ...
                  }:
                  extraSpecialArgs;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."alice@myhost";
        expected = {
          purr = {
            user = "alice";
            host = "myhost";
            arch = "x86_64";
            format = "linux";
            archFormat = "x86_64-linux";
          };
        };
      };
      "root user also gets purr metadata" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    extraSpecialArgs ? { },
                    ...
                  }:
                  extraSpecialArgs;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."root@myserver" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."root@myserver";
        expected = {
          purr = {
            user = "root";
            host = "myserver";
            arch = "x86_64";
            format = "linux";
            archFormat = "x86_64-linux";
          };
        };
      };
      "accepts homeManager as alias for home-manager" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              homeManager = {
                lib.homeManagerConfiguration =
                  {
                    extraSpecialArgs ? { },
                    ...
                  }:
                  extraSpecialArgs;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."alice@myhost";
        expected = {
          purr = {
            user = "alice";
            host = "myhost";
            arch = "x86_64";
            format = "linux";
            archFormat = "x86_64-linux";
          };
        };
      };
      "auto-injects home.username" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    modules ? [ ],
                    ...
                  }:
                  builtins.head modules;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."alice@myhost";
        expected = {
          home.username = "alice";
        };
      };
      "auto-injects homeDirectory for darwin" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    modules ? [ ],
                    ...
                  }:
                  builtins.head modules;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "aarch64-darwin"."alice@macbook" = /tmp;
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          {
            darwin = result."alice@macbook".home or { };
            linux = result."alice@myhost".home or { };
          };
        expected = {
          darwin = {
            username = "alice";
            homeDirectory = "/Users/alice";
          };
          linux = {
            username = "alice";
            homeDirectory = "/home/alice";
          };
        };
      };
      "autoInject = false skips home injection" = {
        expr =
          let
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    modules,
                    ...
                  }:
                  builtins.length modules;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              autoInject = false;
            };
          in
          result."alice@myhost";
        expected = 1;
      };
      "passes sharedOverlays to pkgs import" = {
        expr =
          let
            fakeInputs = {
              nixpkgs =
                {
                  overlays ? [ ],
                  ...
                }@args:
                args;
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    pkgs,
                    ...
                  }:
                  pkgs;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              sharedOverlays = [ "my-ovl" ];
            };
          in
          result."alice@myhost".overlays;
        expected = [ "my-ovl" ];
      };
    };
  };

  buildHomeConfigsExtra = {
    tests = {
      "injects extraModules.home into home configs" = {
        expr =
          let
            extraMod = {
              home.extra = true;
            };
            fakeInputs = {
              nixpkgs = { };
              home-manager = {
                lib.homeManagerConfiguration =
                  {
                    modules ? [ ],
                    ...
                  }:
                  modules;
              };
            };
            result = buildHomeConfigs {
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              extraModules.home = [ extraMod ];
            };
          in
          elem extraMod (result."alice@myhost" or [ ]);
        expected = true;
      };
    };
  };

  # ---- buildSystemConfigs ----
  buildSystemConfigs = {
    tests = {
      "returns nested nixosConfigurations for linux" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
          in
          builtins.attrNames result;
        expected = [ "nixosConfigurations" ];
      };
      "returns nested darwinConfigurations for darwin" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib = { };
              nix-darwin.lib.darwinSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "aarch64-darwin"."mac1" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
          in
          builtins.attrNames result;
        expected = [ "darwinConfigurations" ];
      };
      "accepts darwin as alias for nix-darwin" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib = { };
              darwin.lib.darwinSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "aarch64-darwin"."mac1" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
          in
          builtins.attrNames result;
        expected = [ "darwinConfigurations" ];
      };
      "accepts homeManager alias in system configs" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
              homeManager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
              };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? "home-manager") cfg.modules;
          in
          builtins.attrNames (builtins.head hmMods)."home-manager".users;
        expected = [ "alice" ];
      };
      "auto-creates users.users for linked non-root homes" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux" = {
                  "alice@myhost" = /tmp;
                  "bob@myhost" = /tmp;
                };
              };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            userModules = builtins.filter (m: builtins.isAttrs m && m ? users) cfg.modules;
          in
          builtins.attrNames (builtins.head userModules).users.users;
        expected = [
          "alice"
          "bob"
        ];
      };
      "excludes root from users.users auto-creation" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux"."root@myhost" = /tmp;
              };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            userModules = builtins.filter (m: builtins.isAttrs m && m ? users) cfg.modules;
          in
          userModules;
        expected = [ ];
      };
      "includes root in home-manager.users but not users.users" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux" = {
                  "alice@myhost" = /tmp;
                  "root@myhost" = /tmp;
                };
              };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? "home-manager") cfg.modules;
            hmUsers = builtins.attrNames (builtins.head hmMods)."home-manager".users;
            userMods = builtins.filter (m: builtins.isAttrs m && m ? users) cfg.modules;
            usersUsers =
              if userMods != [ ] then builtins.attrNames (builtins.head userMods).users.users else [ ];
          in
          {
            inherit hmUsers usersUsers;
          };
        expected = {
          hmUsers = [
            "alice"
            "root"
          ];
          usersUsers = [ "alice" ];
        };
      };
      "cross-archformat home matching" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
                "aarch64-linux"."bob@myhost" = /tmp;
              };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? "home-manager") cfg.modules;
          in
          builtins.attrNames (builtins.head hmMods)."home-manager".users;
        expected = [
          "alice"
          "bob"
        ];
      };
      "injects nixpkgsConfig as nixpkgs.config module" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              nixpkgsConfig = {
                allowUnfree = true;
                permittedInsecurePackages = [ "bad-1.0" ];
              };
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (builtins.head cfg.modules).nixpkgs.config;
        expected = {
          allowUnfree = true;
          permittedInsecurePackages = [ "bad-1.0" ];
        };
      };
      "returns empty nixpkgs.config when nixpkgsConfig is {}" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (builtins.head cfg.modules).nixpkgs or { };
        expected = { };
      };
      "injects sharedOverlays as nixpkgs.overlays (mkDefault)" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              autoInject = false;
              sharedOverlays = [
                "overlay1"
                "overlay2"
              ];
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (builtins.head cfg.modules).nixpkgs.overlays;
        expected = [
          "overlay1"
          "overlay2"
        ];
      };
      "system module does NOT set nixpkgs.pkgs" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              nixpkgsConfig = { };
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (builtins.head cfg.modules).nixpkgs ? pkgs || false;
        expected = false;
      };
      "injects extraModules.nixos into linux system configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              extraModules.nixos = [ extraMod ];
            };
            cfg = result.nixosConfigurations.myhost;
          in
          elem extraMod cfg.modules;
        expected = true;
      };
      "injects extraModules.darwin into darwin system configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            fakeInputs = {
              nixpkgs.lib = { };
              darwin.lib.darwinSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "aarch64-darwin"."mac1" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              extraModules.darwin = [ extraMod ];
            };
            cfg = result.darwinConfigurations.mac1;
          in
          elem extraMod cfg.modules;
        expected = true;
      };
      "does not inject darwin extras into linux configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              extraModules.darwin = [ extraMod ];
            };
            cfg = result.nixosConfigurations.myhost;
          in
          elem extraMod cfg.modules;
        expected = false;
      };
      "passes purr metadata as specialArgs (linux)" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem =
                {
                  specialArgs ? { },
                  ...
                }:
                specialArgs;
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
          in
          result.nixosConfigurations.myhost.purr;
        expected = {
          name = "myhost";
          arch = "x86_64";
          format = "linux";
          archFormat = "x86_64-linux";
          homes = [ ];
        };
      };
      "purr.homes includes linked homes" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem =
                {
                  specialArgs ? { },
                  ...
                }:
                specialArgs;
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux" = {
                  "alice@myhost" = /tmp;
                  "bob@myhost" = /tmp;
                };
              };
              inputs = fakeInputs;
            };
          in
          result.nixosConfigurations.myhost.purr.homes;
        expected = [
          {
            user = "alice";
            host = "myhost";
          }
          {
            user = "bob";
            host = "myhost";
          }
        ];
      };
      "passes purr metadata as specialArgs (darwin)" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib = { };
              nix-darwin.lib.darwinSystem =
                {
                  specialArgs ? { },
                  ...
                }:
                specialArgs;
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "aarch64-darwin"."mac1" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
          in
          result.darwinConfigurations.mac1.purr;
        expected = {
          name = "mac1";
          arch = "aarch64";
          format = "darwin";
          archFormat = "aarch64-darwin";
          homes = [ ];
        };
      };
      "cross-archformat homes show in purr.homes" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem =
                {
                  specialArgs ? { },
                  ...
                }:
                specialArgs;
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = {
                "x86_64-linux"."alice@myhost" = /tmp;
                "aarch64-linux"."bob@myhost" = /tmp;
              };
              inputs = fakeInputs;
            };
          in
          builtins.sort (a: b: a.user < b.user) result.nixosConfigurations.myhost.purr.homes;
        expected = [
          {
            user = "alice";
            host = "myhost";
          }
          {
            user = "bob";
            host = "myhost";
          }
        ];
      };
      "auto-injects networking.hostName" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (builtins.head cfg.modules).networking.hostName;
        expected = "myhost";
      };
      "autoInject = false skips hostName injection" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: { inherit modules system; };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          builtins.head cfg.modules;
        expected = /tmp;
      };
    };
  };
}
