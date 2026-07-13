{
  description = "Purr development dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    inputs:
    let
      root = inputs.root or ../.;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      eachSystem = f: builtins.foldl' (acc: system: acc // { "${system}" = f system; }) { } systems;
      perSystem = eachSystem (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = root;
            hooks = {
              deadnix.enable = true;
              nixfmt.enable = true;
              statix.enable = true;
            };
          };
        in
        {
          devShells.default = pkgs.mkShell {
            name = "purr-dev";
            inherit (pre-commit-check) shellHook;
            buildInputs = pre-commit-check.enabledPackages;
          };

          checks = {
            pre-commit = pre-commit-check;
          };
        }
      );
    in
    {
      devShells = builtins.mapAttrs (_: v: v.devShells) perSystem;
      checks = builtins.mapAttrs (_: v: v.checks) perSystem;
    };
}
