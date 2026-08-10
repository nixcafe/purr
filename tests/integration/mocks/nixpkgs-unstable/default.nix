# Second hermetically-importable mock nixpkgs, used to prove `inputsFor`
# replacement switches which input purr consumes to build things.
args:
let
  system = args.system or "x86_64-linux";
in
{
  inherit system;
  config = args.config or { };
  overlays = args.overlays or [ ];

  lib = "pkgs-lib-unstable";
  hello = "hello-unstable-${system}";
  cowsay = "cowsay-unstable-${system}";
  git = "git-unstable-${system}";

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
