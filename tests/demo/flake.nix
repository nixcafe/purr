{
  description = "purr mkFlake integration demo — full build verification";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "path:../..";
    home-manager = {
      url = "github:nix-community/home-manager";
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
