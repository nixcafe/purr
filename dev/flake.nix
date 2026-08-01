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

          # Full per-test report computed in one pure evaluation.
          purrReport = import ../tests/report.nix { inherit (pkgs) lib; };

          # Run the tests directly in the shell (live per-test output).
          purr-test = pkgs.writeShellScriptBin "purr-test" ''
            exec ${root}/tests/run-tests.sh "$@"
          '';
        in
        {
          devShells.default = pkgs.mkShell {
            name = "purr-dev";
            inherit (pre-commit-check) shellHook;
            buildInputs = pre-commit-check.enabledPackages ++ [ purr-test ];
          };

          checks = {
            pre-commit = pre-commit-check;

            # The report goes into `$out`, so `cat result` shows it after a
            # successful build.  On failure the build exits non-zero and the
            # report is printed to the build log (`nix log`).
            purr-tests =
              pkgs.runCommand "purr-tests"
                {
                  failedCount = toString purrReport.failedCount;
                  passAsFile = [ "reportText" ];
                  inherit (purrReport) reportText;
                }
                ''
                  cat "$reportTextPath" > "$out"
                  if [ "$failedCount" != "0" ]; then
                    echo "purr tests FAILED: $failedCount failure(s)" >&2
                    cat "$reportTextPath" >&2
                    exit 1
                  fi
                '';
          };
        }
      );
    in
    {
      devShells = builtins.mapAttrs (_: v: v.devShells) perSystem;
      checks = builtins.mapAttrs (_: v: v.checks) perSystem;
    };
}
