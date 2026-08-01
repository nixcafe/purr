# Shared harness for hermetic integration tests.
#
# Builds purr's lib (exactly like lib.nix), the real-evaluation mocks for
# nixpkgs / home-manager / nix-darwin, and the shim options needed to evaluate
# the generated system/home modules through the real `lib.evalModules`.
{ lib }:
let
  attrsMod = import ../../lib/attrs.nix;
  systemsMod = import ../../lib/systems.nix;
  fs = import ../../lib/fs.nix;
  mods = import ../../lib/modules.nix {
    inherit fs lib;
  };
  confs = import ../../lib/configs.nix {
    inherit lib;
  };
  nsm = import ../../lib/namespacedModules.nix;
  resolver = import ../../lib/resolveDir.nix {
    inherit lib;
  };
  libBuilder = import ../../lib/purrLib.nix {
    inherit lib;
    attrs = attrsMod;
    modules = mods;
    namespacedModules = nsm;
  };
  autoMods = import ../../lib/autoModules.nix {
    modules = mods;
  };
  mkFlakeLib = import ../../lib/mkFlake.nix {
    inherit lib autoMods;
    attrs = attrsMod;
    confs = confs;
    mods = mods;
    nsm = nsm;
    purrLib = libBuilder;
    resolveDir = resolver;
    systems = systemsMod;
  };

  systemShim = {
    options = {
      networking.hostName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      system.stateVersion = lib.mkOption {
        type = lib.types.str;
      };
      system.build.toplevel = lib.mkOption {
        type = lib.types.raw;
      };
      system.build.images = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
      services.openssh.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      users.users = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
      };
      nixpkgs.config = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      nixpkgs.overlays = lib.mkOption {
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
      "home-manager".users = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      "home-manager".useGlobalPkgs = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      "home-manager".useUserPackages = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      "home-manager".extraSpecialArgs = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    };
  };

  homeShim = {
    options = {
      home.username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      home.homeDirectory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      home.stateVersion = lib.mkOption {
        type = lib.types.str;
      };
      home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
      activationPackage = lib.mkOption {
        type = lib.types.raw;
        default = null;
      };
    };
  };

  moduleShim = {
    options = {
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.raw;
        default = [ ];
      };
      services.openssh.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  evalNixosSystem =
    {
      modules,
      system,
      specialArgs,
    }:
    let
      eval = lib.evalModules {
        modules = [ systemShim ] ++ modules;
        inherit specialArgs;
      };
    in
    {
      _type = "nixosSystem";
      inherit modules system specialArgs;
      inherit (eval) config;
      pkgs = {
        inherit system;
      };
    };

  evalDarwinSystem =
    {
      modules,
      system,
      specialArgs,
    }:
    let
      eval = lib.evalModules {
        modules = [ systemShim ] ++ modules;
        inherit specialArgs;
      };
    in
    {
      _type = "darwinSystem";
      inherit modules system specialArgs;
      inherit (eval) config;
      pkgs = {
        inherit system;
      };
    };

  evalHomeConfiguration =
    {
      pkgs,
      modules,
      extraSpecialArgs,
    }:
    let
      eval = lib.evalModules {
        modules = [ homeShim ] ++ modules;
        specialArgs = extraSpecialArgs;
      };
    in
    {
      _type = "homeConfiguration";
      inherit modules extraSpecialArgs pkgs;
      inherit (eval) config;
      activationPackage = eval.config.activationPackage;
    };

  nixpkgsMock = {
    outPath = ./mocks/nixpkgs;
    __toString = self: self.outPath;
    lib = lib // {
      nixosSystem = evalNixosSystem;
    };
  };

  homeManagerMock = {
    lib.homeManagerConfiguration = evalHomeConfiguration;
    nixosModules.home-manager = {
      _file = "mock-home-manager-nixos";
    };
    darwinModules.home-manager = {
      _file = "mock-home-manager-darwin";
    };
  };

  darwinMock = {
    lib.darwinSystem = evalDarwinSystem;
  };

  inputs = {
    nixpkgs = nixpkgsMock;
    home-manager = homeManagerMock;
    nix-darwin = darwinMock;
  };
in
{
  inherit
    inputs
    mkFlakeLib
    moduleShim
    homeShim
    systemShim
    ;
  inherit (mkFlakeLib) mkFlake;
}
