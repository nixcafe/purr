{
  description = "Purr — a lean Nix flake library";

  inputs = {
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  };

  outputs =
    inputs:
    let
      lib = import ./lib.nix {
        inherit (inputs.nixpkgs-lib) lib;
      };

      # Use flake-compat to resolve dev flake's nixpkgs input
      flake-compat = import ./vendor/flake-compat { src = ./dev; };

      # Re-evaluate dev flake with root source + resolved inputs
      devFlake = import ./dev/flake.nix;
      dev = devFlake.outputs {
        nixpkgs = flake-compat.outputs.inputs.nixpkgs;
        git-hooks = flake-compat.outputs.inputs.git-hooks;
        root = ./.;
      };
    in
    {
      inherit lib;
      flakeModules = {
        default = ./flake-module.nix;
      };
      templates = {
        default = {
          path = ./template/default;
          description = ''
            A minimal flake using purr standalone (mkFlake).
          '';
        };
        flake-parts = {
          path = ./template/flake-parts;
          description = ''
            A minimal flake using purr with flake-parts.
          '';
        };
      };
      devShells = dev.devShells or { };
      checks = dev.checks or { };
    };
}
