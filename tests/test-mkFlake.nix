# Tests for lib/mkFlake.nix — end-to-end integration
{ lib }:
let
  inherit (lib)
    attrNames
    elem
    filter
    length
    ;

  attrsMod = import ../lib/attrs.nix;
  systemsMod = import ../lib/systems.nix;
  fs = import ../lib/fs.nix;
  mods = import ../lib/modules.nix {
    inherit fs lib;
  };
  confs = import ../lib/configs.nix {
    inherit lib;
  };
  nsm = import ../lib/namespacedModules.nix;
  resolver = import ../lib/resolveDir.nix {
    inherit lib;
  };
  libBuilder = import ../lib/purrLib.nix {
    inherit lib;
    attrs = attrsMod;
    modules = mods;
    namespacedModules = nsm;
  };
  autoMods = import ../lib/autoModules.nix {
    modules = mods;
  };

  mkFlakeLib = import ../lib/mkFlake.nix {
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
  # ---- systems discovery ----
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
          elem "nixosConfigurations" (attrNames result);
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
          in
          attrNames (result.nixosConfigurations or { });
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
          in
          attrNames (result.darwinConfigurations or { });
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
            md = result.nixosConfigurations.myhost.specialArgs.purr or null;
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
          in
          result.nixosConfigurations.myhost.specialArgs ? lib;
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
          in
          result.nixosConfigurations.myhost.specialArgs.namespace;
        expected = "demo-ns";
      };
    };
  };

  # ---- homes discovery ----
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
            md = result.homeConfigurations."alice@myhost".extraSpecialArgs.purr or null;
          in
          (md != null) && (md.user == "alice") && (md.host == "myhost");
        expected = true;
      };
      "home extraSpecialArgs contains purrLib" = {
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
          in
          result.homeConfigurations."alice@myhost".extraSpecialArgs ? purrLib;
        expected = true;
      };
    };
  };

  # ---- systems + homes integration ----
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
          in
          attrNames ((builtins.head hmMods)."home-manager".users or { });
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
          in
          (result.nixosConfigurations.myhost.specialArgs.purr or { }).homes;
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
            hn = (builtins.head result.nixosConfigurations.myhost.modules).networking or { };
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
          in
          builtins.isPath (builtins.head result.nixosConfigurations.myhost.modules);
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
          in
          (builtins.head result.homeConfigurations."alice@myhost".modules).home or { };
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
          in
          elem extraMod result.nixosConfigurations.myhost.modules;
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
          in
          elem extraMod result.homeConfigurations."alice@myhost".modules;
        expected = true;
      };
    };
  };

  # ---- full pipeline ----
  fullPipeline = {
    tests = {
      "full pipeline output keys" = {
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
          in
          attrNames result;
        expected = [
          "darwinModules"
          "homeConfigurations"
          "homeModules"
          "lib"
          "nixosConfigurations"
          "nixosModules"
        ];
      };
      "lib namespace is accessible" = {
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
          in
          result.lib.demo or null != null;
        expected = true;
      };
      "system specialArgs has namespaced lib" = {
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
          in
          (result.nixosConfigurations.myhost.specialArgs.lib or { }) ? "demo";
        expected = true;
      };
      "home extraSpecialArgs has purrLib" = {
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
          in
          result.homeConfigurations."alice@myhost".extraSpecialArgs.purrLib or null != null;
        expected = true;
      };
    };
  };

  # ---- mkFlake options ----
  flattenLib = {
    tests = {
      "flattenLib true produces flat lib structure" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = "demo";
              libDir = "lib";
              flattenLib = true;
              autoInject = false;
            };
            nsLib = result.lib.demo or null;
          in
          if nsLib != null then builtins.sort (a: b: a < b) (attrNames nsLib) else [ ];
        expected = [
          "helperUtil"
          "utilFunc"
        ];
      };
    };
  };

  bundleExtraModules = {
    tests = {
      "bundleExtraModules = false excludes extra from default bundle" = {
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
              modulesDir = "modules";
              bundleModules = true;
              bundleExtraModules = false;
              extraModules.nixos = [ extraMod ];
              namespace = null;
              autoInject = false;
            };
            dflt = result.nixosModules.default or null;
            imports = if dflt != null then dflt.imports or [ ] else [ ];
          in
          elem extraMod imports;
        expected = false;
      };
    };
  };

  customModuleTypes = {
    tests = {
      "custom moduleTypes are honored" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              modulesDir = "modules";
              moduleTypes = {
                nixos = [ "home" ];
              };
              namespace = null;
              autoInject = false;
            };
          in
          attrNames (result.nixosModules or { });
        expected = [ "desktop" ];
      };
    };
  };

  customSystems = {
    tests = {
      "custom systems parameter works" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              systems = [ "x86_64-linux" ];
              namespace = null;
              autoInject = false;
            };
          in
          attrNames (result.darwinModules or { });
        expected = [ ];
      };
    };
  };

  outputsBuilder = {
    tests = {
      "outputsBuilder produces custom output" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = null;
              autoInject = false;
              outputsBuilder = { system, ... }: { specialOutput = "hello-${system}"; };
            };
          in
          elem "specialOutput" (attrNames result);
        expected = true;
      };
      "outputsBuilder pivots per-system to per-key" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = null;
              autoInject = false;
              outputsBuilder = { system, ... }: { ping = "pong-${system}"; };
            };
          in
          attrNames (result.ping or { });
        expected = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
      };
    };
  };

  packagesByName = {
    tests = {
      "packagesByName = false only finds regular packages" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              packagesByName = false;
              namespace = null;
              autoInject = false;
            };
          in
          attrNames (result.packages."x86_64-linux" or { });
        expected = [
          "hello"
          "lib-check"
          "spread-test"
        ];
      };
      "packagesByName = true finds both regular and by-name" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              packagesByName = true;
              namespace = null;
              autoInject = false;
            };
          in
          builtins.sort (a: b: a < b) (attrNames (result.packages."x86_64-linux" or { }));
        expected = [
          "badshard"
          "cowsay"
          "hello"
          "lib-check"
          "spread-test"
        ];
      };
    };
  };

  extraArgs = {
    tests = {
      "extraArgs flows to outputsBuilder" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = null;
              autoInject = false;
              extraArgs = {
                myConstructor = "builder";
              };
              outputsBuilder =
                { myConstructor, ... }:
                {
                  gotConstructor = myConstructor;
                };
            };
          in
          result.gotConstructor."x86_64-linux" or null;
        expected = "builder";
      };
      "extraArgs flows to system specialArgs" = {
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
              extraArgs = {
                myCustom = "extra-value";
              };
            };
          in
          result.nixosConfigurations.myhost.specialArgs.myCustom or null;
        expected = "extra-value";
      };
      "extraArgs flows to standalone home extraSpecialArgs" = {
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
              extraArgs = {
                myHomeCustom = "home-value";
              };
            };
          in
          result.homeConfigurations."alice@myhost".extraSpecialArgs.myHomeCustom or null;
        expected = "home-value";
      };
      "extraArgs does not override purr's own keys in specialArgs" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
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
      "extraArgs flows to packages" = {
        expr =
          let
            inputs = {
              nixpkgs = mkNixpkgs mkNixpkgsLib;
            };
            result = mkFlake {
              inherit inputs;
              src = fixturesDir;
              namespace = null;
              autoInject = false;
              extraArgs = {
                myCustom = "pkg-value";
              };
            };
            pkg = result.packages."x86_64-linux".extra-test or null;
          in
          if pkg != null then pkg.myCustom or null else null;
        expected = "pkg-value";
      };
      "extraArgs flows to linked home extraSpecialArgs" = {
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
              extraArgs = {
                linkedHomeCustom = "linked-value";
              };
            };
            cfg = result.nixosConfigurations.myhost;
          in
          builtins.any (
            m:
            builtins.isAttrs m
            && m ? "home-manager"
            && m."home-manager".extraSpecialArgs.linkedHomeCustom or null == "linked-value"
          ) cfg.modules;
        expected = true;
      };
    };
  };
}
