# Tests for mkFlake with systems, homes, lib — end-to-end integration
# Verifies no circular dependencies between module discovery, lib building,
# system config creation, and home config creation.
{
  lib,
}:
let
  mkFlakeLib = import ../lib/mkFlake.nix {
    attrs = import ../lib/attrs.nix;
    configs = import ../lib/configs.nix { inherit lib; };
    systems = import ../lib/systems.nix;
    inherit lib;
    modules = import ../lib/modules.nix {
      fs = import ../lib/fs.nix;
      inherit lib;
    };
    namespacedModules = import ../lib/namespacedModules.nix;
  };

  inherit (mkFlakeLib) mkFlake;
  inherit (lib)
    attrNames
    attrValues
    elem
    filter
    length
    ;

  fixturesDir = ./fixtures;

  mkNixpkgsLib = {
    nixosSystem =
      {
        modules ? [ ],
        system,
        specialArgs,
      }:
      {
        _type = "nixosSystem";
        inherit modules system specialArgs;
      };
  };

  mkNixpkgs = pkgsLib: {
    lib = pkgsLib;
    nixosModules.readOnlyPkgs = "readOnlyPkgs";
  };

  mkHomeManager = {
    lib.homeManagerConfiguration =
      {
        modules,
        extraSpecialArgs,
        ...
      }:
      {
        _type = "homeConfiguration";
        inherit modules extraSpecialArgs;
      };
    nixosModules.home-manager = "hm-nixos";
    darwinModules.home-manager = "hm-darwin";
  };

  mkDarwin = {
    lib.darwinSystem =
      {
        modules,
        system,
        specialArgs,
      }:
      {
        _type = "darwinSystem";
        inherit modules system specialArgs;
      };
  };
in
{
  systemsOnly = {
    tests = {
      "discovers and builds system configs" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
            };
          in
          attrNames result;
        expected = [
          "darwinModules"
          "homeModules"
          "nixosModules"
        ];
      };

      "returns empty when no systems dir" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "nonexistent";
              namespace = null;
            };
          in
          builtins.elem "nixosConfigurations" (attrNames result);
        expected = false;
      };

      "nixosConfigurations contains discovered hosts" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
            };
            nixos = result.nixosConfigurations or { };
          in
          attrNames nixos;
        expected = [ "myhost" ];
      };

      "darwinConfigurations contains macbook" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              darwin = mkDarwin;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
            };
            darwinCfgs = result.darwinConfigurations or { };
          in
          attrNames darwinCfgs;
        expected = [ "macbook" ];
      };

      "system specialArgs contains purr metadata" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            md = cfg.specialArgs.purr or null;
          in
          (md != null) && (md.name == "myhost") && (md.arch == "x86_64") && (md.format == "linux");
        expected = true;
      };

      "system specialArgs contains lib" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = "demo-ns";
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            hasLib = cfg.specialArgs ? lib;
          in
          hasLib;
        expected = true;
      };

      "system specialArgs contains namespace" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = "demo-ns";
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          cfg.specialArgs.namespace;
        expected = "demo-ns";
      };
    };
  };

  homesOnly = {
    tests = {
      "builds home configs when home-manager present" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
          in
          attrNames (result.homeConfigurations or { });
        expected = [ "alice@myhost" ];
      };

      "returns empty when no home-manager" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
          in
          result.homeConfigurations or { };
        expected = { };
      };

      "home extraSpecialArgs contains purr metadata" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              homeManager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
            cfg = result.homeConfigurations."alice@myhost";
            md = cfg.extraSpecialArgs.purr or null;
          in
          (md != null) && (md.user == "alice") && (md.host == "myhost");
        expected = true;
      };

      "home extraSpecialArgs contains lib as purrLib" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = "demo-ns";
              autoInject = false;
            };
            cfg = result.homeConfigurations."alice@myhost";
          in
          cfg.extraSpecialArgs ? purrLib;
        expected = true;
      };
    };
  };

  systemsAndHomes = {
    tests = {
      "linked homes are injected into matching system" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = filter (m: builtins.isAttrs m && m ? "home-manager") cfg.modules;
          in
          length hmMods > 0;
        expected = true;
      };

      "home-manager users includes linked user" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            hmMods = filter (m: builtins.isAttrs m && m ? "home-manager") cfg.modules;
            hmMod = builtins.head hmMods;
            users = attrNames (hmMod."home-manager".users or { });
          in
          users;
        expected = [ "alice" ];
      };

      "purr.homes metadata reflects linked homes" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
          in
          (cfg.specialArgs.purr or { }).homes;
        expected = [
          {
            user = "alice";
            host = "myhost";
          }
        ];
      };

      "homeConfigurations also built standalone" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              homesDir = "homes";
              namespace = null;
              autoInject = false;
            };
          in
          attrNames (result.homeConfigurations or { });
        expected = [ "alice@myhost" ];
      };

      "autoInject hostName into system" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
            };
            cfg = result.nixosConfigurations.myhost;
            firstModule = builtins.head cfg.modules;
            hn = firstModule.networking or { };
          in
          hn.hostName or null;
        expected = "myhost";
      };

      "autoInject = false skips hostName" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            firstModule = builtins.head cfg.modules;
          in
          builtins.isPath firstModule;
        expected = true;
      };

      "autoInject home.username" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = null;
            };
            cfg = result.homeConfigurations."alice@myhost";
            firstModule = builtins.head cfg.modules;
          in
          firstModule.home or { };
        expected = {
          username = "alice";
        };
      };

      "injects extraModules.nixos into all system configs" = {
        expr =
          let
            extraMod = {
              services.extra = true;
            };
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systemsDir = "systems";
              namespace = null;
              autoInject = false;
              extraModules.nixos = [ extraMod ];
            };
            cfg = result.nixosConfigurations.myhost;
          in
          elem extraMod cfg.modules;
        expected = true;
      };

      "injects extraModules.home into home configs" = {
        expr =
          let
            extraMod = {
              home.extra = true;
            };
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              homesDir = "homes";
              namespace = null;
              autoInject = false;
              extraModules.home = [ extraMod ];
            };
            cfg = result.homeConfigurations."alice@myhost";
          in
          elem extraMod cfg.modules;
        expected = true;
      };
    };
  };

  fullPipeline = {
    tests = {
      "full pipeline with lib + modules + systems + homes" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              modulesDir = "modules";
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
              bundleModules = true;
            };
            outputs = attrNames result;
          in
          outputs;
        expected = [
          "darwinModules"
          "homeConfigurations"
          "homeModules"
          "lib"
          "nixosConfigurations"
          "nixosModules"
        ];
      };

      "full pipeline lib namespace is accessible" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
            nsLib = result.lib.demo or null;
          in
          nsLib != null;
        expected = true;
      };

      "full pipeline system specialArgs has namespaced lib" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
            cfg = result.nixosConfigurations.myhost;
            sargs = cfg.specialArgs;
          in
          (sargs.lib or { }) ? "demo";
        expected = true;
      };

      "full pipeline home extraSpecialArgs has purrLib" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
              home-manager = mkHomeManager;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              systemsDir = "systems";
              homesDir = "homes";
              autoInject = false;
            };
            cfg = result.homeConfigurations."alice@myhost";
          in
          cfg.extraSpecialArgs.purrLib or null != null;
        expected = true;
      };
    };
  };
}
