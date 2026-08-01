# Hermetic mock nixpkgs used by the integration tests.
#
# mkFlake calls `import inputs.nixpkgs { system; config; overlays; }` to build
# the per-system `pkgs` set.  This file is that import target: it must return
# a function taking the standard nixpkgs arguments and produce a small,
# deterministic `pkgs`-like attrset that fixture modules can consume.
args:
let
  system = args.system or "x86_64-linux";
in
{
  inherit system;
  config = args.config or { };
  overlays = args.overlays or [ ];

  lib = "pkgs-lib";
  stdenv = {
    inherit system;
    _type = "stdenv";
  };
  hello = "hello-drv-${system}";
  cowsay = "cowsay-${system}";
  git = "git-${system}";

  writeText = name: text: {
    _type = "writeText";
    inherit name text;
  };
  runCommand = name: attrs: body: {
    _type = "runCommand";
    inherit name attrs body;
  };
  mkShell = attrs: {
    _type = "mkShell";
    inherit attrs;
  };
}
