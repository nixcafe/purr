{
  description = "Purr development dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          pre-commit-check = inputs.git-hooks.lib.${system}.run {
            src = root;
            hooks = {
              deadnix = {
                enable = true;
                entry = "${pkgs.deadnix}/bin/deadnix -L";
              };
              nixfmt.enable = true;
              statix.enable = true;
            };
          };

          purrTests = import ../tests/default.nix { inherit (pkgs) lib; };

          purrTestsFailed = builtins.length purrTests > 0;

          purrTestsMsg = builtins.concatStringsSep "\n" (
            builtins.map (
              f:
              "  FAIL: ${f.name}\n    expected: ${builtins.toJSON f.expected}\n    got: ${builtins.toJSON f.result}"
            ) purrTests
          );
        in
        {
          devShells.default = pkgs.mkShell {
            name = "purr-dev";
            inherit (pre-commit-check) shellHook;
            buildInputs = pre-commit-check.enabledPackages;
          };

          checks = {
            pre-commit = pre-commit-check;
            purr-tests =
              if purrTestsFailed then
                builtins.throw "purr tests FAILED:\n${purrTestsMsg}"
              else
                pkgs.runCommand "purr-tests" { } "touch $out";
          };
        }
      );
    in
    {
      devShells = builtins.mapAttrs (_: v: v.devShells) perSystem;
      checks = builtins.mapAttrs (_: v: v.checks) perSystem;
    };
}
