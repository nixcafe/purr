# Unit tests for lib/resolveInput.nix — effective-input role resolution.
{ lib }:
let
  inherit (import ../../lib/resolveInput.nix) defaultHomeManager defaultNixDarwin resolveRole;
in
{
  resolveRole = {
    tests = {
      "returns the effective input for a present key" = {
        expr = resolveRole {
          effectiveInputs = {
            nixpkgs = "np";
            other = "x";
          };
          key = "nixpkgs";
          context = "host 'server'";
        };
        expected = "np";
      };
      "returns the effective input for an arbitrary key" = {
        expr = resolveRole {
          effectiveInputs.nixpkgs-unstable = "npu";
          key = "nixpkgs-unstable";
          context = "host 'server'";
        };
        expected = "npu";
      };
      "throws when the key is missing from effective inputs" = {
        expr =
          (builtins.tryEval (resolveRole {
            effectiveInputs = {
              nixpkgs = "np";
            };
            key = "nixpkgs-unstable";
            context = "host 'server'";
          })).success;
        expected = false;
      };
      "throws when the key is not a string" = {
        expr =
          let
            result = builtins.tryEval (resolveRole {
              effectiveInputs = {
                nixpkgs = "np";
              };
              key = [ "nixpkgs" ];
              context = "host 'server'";
            });
          in
          result.success;
        expected = false;
      };
      "a missing key with string default still resolves" = {
        expr = resolveRole {
          effectiveInputs.nixpkgs = "np";
          key = "nixpkgs";
          context = "host 'server'";
        };
        expected = "np";
      };
    };
  };

  defaultHomeManager = {
    tests = {
      "prefers home-manager" = {
        expr = defaultHomeManager {
          home-manager = { };
        };
        expected = "home-manager";
      };
      "falls back to homeManager" = {
        expr = defaultHomeManager {
          homeManager = { };
        };
        expected = "homeManager";
      };
      "returns null when neither is present" = {
        expr = defaultHomeManager {
          nixpkgs = { };
        };
        expected = null;
      };
    };
  };

  defaultNixDarwin = {
    tests = {
      "prefers nix-darwin" = {
        expr = defaultNixDarwin {
          nix-darwin = { };
        };
        expected = "nix-darwin";
      };
      "falls back to darwin" = {
        expr = defaultNixDarwin {
          darwin = { };
        };
        expected = "darwin";
      };
      "returns null when neither is present" = {
        expr = defaultNixDarwin {
          nixpkgs = { };
        };
        expected = null;
      };
    };
  };
}
