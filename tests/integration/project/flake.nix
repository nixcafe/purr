{
  description = "purr integration test project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "path:../../..";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin.url = "github:LnL7/nix-darwin";
  };

  outputs =
    inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      namespace = "demo";
      bundleModules = true;
      packagesByName = true;
      hydraJobs = {
        enable = true;
        systems = [ "x86_64-linux" ];
      };
      hosts.server.meta = {
        tier = "prod";
        region = "us-east";
      };
      outputsBuilder =
        { system, ... }:
        {
          customPerSystem = "custom-${system}";
        };
    };
}
