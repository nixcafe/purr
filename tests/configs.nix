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
          channelsConfig = { };
        };
        expected = { };
      };

      "returns empty when no homes discovered" = {
        expr = buildHomeConfigs {
          discoveredHomes = { };
          inputs = { };
          channelsConfig = { };
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
              channelsConfig = { };
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
              channelsConfig = { };
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
    };
  };
}
