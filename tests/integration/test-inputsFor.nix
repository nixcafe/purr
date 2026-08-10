# Integration tests: per-host input replacement via `inputsFor` + meta role
# keys. A second hermetically-importable nixpkgs mock is wired through
# `inputsFor`; `hosts.<name>.meta.nixpkgs` makes `server` build from it, while
# the other hosts and the linked/standalone homes fall back to the default.
{ lib }:
let
  harness = import ./harness.nix {
    inherit lib;
  };

  projectDir = ./project;

  inputs' = harness.inputs // {
    nixpkgs-unstable = harness.makeNixpkgsMock {
      marker = "unstable";
      importTarget = ./mocks/nixpkgs-unstable;
    };
  };

  result = harness.mkFlake {
    inputs = inputs';
    src = projectDir;
    namespace = "demo";
    hosts.server.meta = {
      tier = "prod";
      region = "us-east";
      nixpkgs = "nixpkgs-unstable";
    };
    inputsFor =
      { inputs, ... }:
      {
        inherit (inputs) nixpkgs;
        "home-manager" = inputs.home-manager;
        "nix-darwin" = inputs.nix-darwin;
        "nixpkgs-unstable" = inputs."nixpkgs-unstable";
      };
  };
in
{
  hostNixpkgsRole = {
    tests = {
      "server builds from the meta-selected nixpkgs" = {
        expr = result.nixosConfigurations.server.nixpkgsMarker or null;
        expected = "unstable";
      };
      "iso host without an override keeps the default nixpkgs" = {
        expr = result.imageRecipes.iso.cfg.nixpkgsMarker or null;
        expected = null;
      };
      "server config still evaluates through the real module system" = {
        expr = {
          hostName = result.nixosConfigurations.server.config.networking.hostName;
          stateVersion = result.nixosConfigurations.server.config.system.stateVersion;
        };
        expected = {
          hostName = "server";
          stateVersion = "24.11";
        };
      };
      "modules still see the raw flake inputs" = {
        expr = result.nixosConfigurations.server.config.demo.inputsRef.hasDefiningInputs;
        expected = true;
      };
    };
  };

  homeNixpkgsRole = {
    tests = {
      "standalone home inherits its linked system's nixpkgs role" = {
        expr = result.homeConfigurations."alice@server".pkgs.hello;
        expected = "hello-unstable-x86_64-linux";
      };
      "darwin home without an override keeps the default nixpkgs" = {
        expr = result.homeConfigurations."alice@macbook".pkgs.hello;
        expected = "hello-drv-aarch64-darwin";
      };
    };
  };

  bridgedHomes = {
    tests = {
      "bridged homes on the overridden host use the selected home-manager bridge" = {
        expr = lib.attrNames (result.nixosConfigurations.server.config."home-manager".users or { });
        expected = [
          "alice"
          "root"
        ];
      };
    };
  };
}
