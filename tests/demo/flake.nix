{
  description = "purr mkFlake integration demo — full build verification";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    purr.url = "path:../..";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      namespace = "demo";
      bundleModules = true;
      templatesRecursive = false;
      outputsBuilder =
        {
          pkgs,
          system,
          lib,
          namespace,
          ...
        }:
        {
          formatter = pkgs.hello;
        };
    };
}
