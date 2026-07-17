# Tests for lib/configs.nix — buildHomeConfigs, buildSystemConfigs
{
  lib,
}:
let
  inherit (import ../lib/configs.nix { inherit lib; })
    buildHomeConfigs
    buildSystemConfigs
    ;
in
{
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

      "injects purr.user and purr.host via extraSpecialArgs" = {
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
            homes = {
              "x86_64-linux"."alice@myhost" = /tmp;
            };
            result = buildHomeConfigs {
              discoveredHomes = homes;
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."alice@myhost";
        expected = {
          purr = {
            user = "alice";
            host = "myhost";
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
            homes = {
              "x86_64-linux"."root@myserver" = /tmp;
            };
            result = buildHomeConfigs {
              discoveredHomes = homes;
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."root@myserver";
        expected = {
          purr = {
            user = "root";
            host = "myserver";
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
            homes = {
              "x86_64-linux"."alice@myhost" = /tmp;
            };
            result = buildHomeConfigs {
              discoveredHomes = homes;
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
          in
          result."alice@myhost";
        expected = {
          purr = {
            user = "alice";
            host = "myhost";
          };
        };
      };
    };
  };

  buildSystemConfigs = {
    tests = {
      "returns nested nixosConfigurations for linux" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
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
              nix-darwin.lib.darwinSystem = { modules, system }: {
                inherit modules system;
              };
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
              darwin.lib.darwinSystem = { modules, system }: {
                inherit modules system;
              };
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

      "accepts homeManager alias for home-manager in system configs" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
              homeManager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            homes = {
              "x86_64-linux"."alice@myhost" = /tmp;
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = homes;
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? home-manager) cfg.modules;
          in
          builtins.attrNames (builtins.head hmMods).home-manager.users;
        expected = [ "alice" ];
      };

      "auto-creates users.users for linked non-root homes" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            homes = {
              "x86_64-linux" = {
                "alice@myhost" = /tmp;
                "bob@myhost" = /tmp;
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = homes;
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
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            homes = {
              "x86_64-linux" = {
                "root@myhost" = /tmp;
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = homes;
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
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            homes = {
              "x86_64-linux" = {
                "alice@myhost" = /tmp;
                "root@myhost" = /tmp;
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = homes;
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? home-manager) cfg.modules;
            hmUsers = builtins.attrNames (builtins.head hmMods).home-manager.users;
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
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
              home-manager = {
                nixosModules.home-manager = "hm-mod";
                darwinModules.home-manager = "hm-darwin";
              };
            };
            homes = {
              "x86_64-linux"."alice@myhost" = /tmp;
              "aarch64-linux"."bob@myhost" = /tmp;
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = homes;
              inputs = fakeInputs;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = builtins.filter (m: builtins.isAttrs m && m ? home-manager) cfg.modules;
            hmUsers = builtins.attrNames (builtins.head hmMods).home-manager.users;
          in
          hmUsers;
        expected = [
          "alice"
          "bob"
        ];
      };

      "injects nixpkgsConfig as nixpkgs.config module" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
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
            };
            cfg = result.nixosConfigurations.myhost;
            firstModule = builtins.head cfg.modules;
          in
          firstModule.nixpkgs.config;
        expected = {
          allowUnfree = true;
          permittedInsecurePackages = [ "bad-1.0" ];
        };
      };

      "returns {} as config when nixpkgsConfig is empty" = {
        expr =
          let
            fakeInputs = {
              nixpkgs.lib.nixosSystem = { modules, system }: {
                inherit modules system;
              };
            };
            result = buildSystemConfigs {
              discoveredSystems = {
                "x86_64-linux"."myhost" = /tmp;
              };
              discoveredHomes = { };
              inputs = fakeInputs;
              nixpkgsConfig = { };
            };
            cfg = result.nixosConfigurations.myhost;
            firstModule = builtins.head cfg.modules;
          in
          firstModule;
        expected = /tmp;
      };
    };
  };
}
