# purr

purr builds a Nix flake from the files in your project. It discovers modules, packages,
systems, homes, and the other outputs from the directory layout, so you do not have to
wire them together by hand.

purr depends on `nixpkgs-lib`. The standalone API is a single `mkFlake` call, and the
flake-parts module exposes the same discovery.

## Quick start

Start from a template:

```bash
# Standalone (mkFlake)
nix flake init -t github:nixcafe/purr

# With flake-parts
nix flake init -t github:nixcafe/purr#flake-parts
```

Or add purr to an existing flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "https://flakehub.com/f/nixcafe/purr/0.1.*.tar.gz";
  };

  outputs = inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      namespace = "myproject";
    };
}
```

## What purr discovers

`src` is scanned for these directories:

```
.
├── flake.nix
├── modules/              → nixosModules, darwinModules, homeModules
├── packages/             → packages.<system>.* (also registered into pkgs.*)
├── legacyPackages/       → legacyPackages.<system>.*
├── shells/               → devShells.<system>.*
├── checks/               → checks.<system>.*
├── apps/                 → apps.<system>.*
├── overlays/             → overlays.*
├── templates/            → templates.*
├── formatters/           → formatter.<system>
├── hydraJobs/            → hydraJobs.* (when enabled)
├── lib/                  → lib.<namespace>.*
├── systems/              → nixosConfigurations, darwinConfigurations
└── homes/                → homeConfigurations
```

## Modules

Modules under `modules/` are exposed by their subdirectory path:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → merged into nixos + darwin
```

The default `moduleTypes` maps `nixos/` and `shared/` to `nixosModules`, `darwin/` and
`shared/` to `darwinModules`, and `home/` to `homeModules`. See
[Module System](/modules) for the mappings and customisation.

## Namespaces

When `namespace` is set, purr passes it to every discovered module and exports the
project lib under `lib.<namespace>`:

```nix
{ config, lib, namespace, ... }:
let
  cfg = config.${namespace}.my-module;
in
{
  options.${namespace}.my-module.enable = lib.mkEnableOption "my module";
  config = lib.mkIf cfg.enable { /* ... */ };
}
```

## Shared lib

A `lib/` directory is available as `lib.<namespace>.*` in every module, package,
shell, and check:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

Access the functions with `lib.<namespace>.keys`, `lib.<namespace>.utils`, and so on.

## Systems and homes

Systems and homes use the `<arch>-<format>/<name>` layout:

```
systems/
├── x86_64-linux/server/default.nix    → nixosConfigurations.server
└── aarch64-darwin/macbook/default.nix → darwinConfigurations.macbook

homes/
└── x86_64-linux/alice@server/default.nix  → homeConfigurations."alice@server"
```

A home named `<user>@<host>` is linked to the matching host when home-manager is
available. See [Systems & Homes](/systems-homes) and [Host Meta](/meta).

## hydraJobs

When enabled, `hydraJobs` mirrors buildable outputs and adds jobs from a `hydraJobs/`
directory. See [hydraJobs](/hydrajobs).

## Integration modes

* [flake-parts](/flake-parts): import `inputs.purr.flakeModules.default`.
* [mkFlake](/mkflake): call `inputs.purr.lib.mkFlake` without flake-parts.

## Project layout

See [Directory Structure](/directory-structure) for the full layout.

## API reference

The library exports 43 functions. See [API Reference](/api).
