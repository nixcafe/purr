{
  description = "A purr project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "github:nixcafe/purr";
  };

  outputs =
    inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      namespace = "myproject";
      outputsBuilder =
        {
          pkgs,
          system,
          lib,
          namespace,
          ...
        }:
        {
          formatter = pkgs.nixfmt;
        };
    };
}
