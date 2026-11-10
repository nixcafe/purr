<h1 align="center">purr</h1>
<p align="center">
  A Nix flake framework based on directory layout, namespaces, and modules.
  <br />
  <a href="https://purr.nixcafe.org"><strong>purr.nixcafe.org</strong></a>
</p>

<p align="center">
  <a href="https://flakehub.com/flake/nixcafe/purr"><img src="https://img.shields.io/badge/FlakeHub-nixcafe%2Fpurr-blue?logo=nixos" alt="FlakeHub" /></a>
  <a href="https://github.com/nixcafe/purr/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-CC0--1.0-brightgreen" alt="License" /></a>
</p>

---

## What it does

purr builds a flake from the files in your project. It discovers modules, packages,
systems, homes, and the other outputs from the directory layout, so you don't have to
wire them together by hand.

purr only depends on `nixpkgs-lib` (about 2 MB), and the API is small.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "https://flakehub.com/f/nixcafe/purr/0.1.*.tar.gz";
  };

  outputs = inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
    };
}
```

The directory layout looks like this:

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
├── hydraJobs/            → hydraJobs.* (CI jobs, opt-in)
├── lib/                  → lib.<namespace>.* (shared across all modules)
├── systems/              → nixosConfigurations, darwinConfigurations
└── homes/                → homeConfigurations
```

## Getting started

Start from one of the templates:

```bash
# Standalone (mkFlake)
nix flake init -t github:nixcafe/purr

# With flake-parts
nix flake init -t github:nixcafe/purr#flake-parts
```

## Usage

purr works either on its own or as a flake-parts module.

### Standalone (`mkFlake`)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "github:nixcafe/purr";
  };

  outputs = inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      namespace = "myproject";
      outputsBuilder = { pkgs, ... }: {
        formatter = pkgs.nixfmt;
      };
    };
}
```

### flake-parts module

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purr.url = "github:nixcafe/purr";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.purr.flakeModules.default ];
      purr = {
        enable = true;
        src = ./.;
        namespace = "myproject";
      };
    };
}
```

## How it works

### Modules

Modules under `modules/` are exposed by their subdirectory path:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → merged into nixos + darwin
```

Change the mapping with `moduleTypes`:

```nix
moduleTypes = {
  nixos = ["nixos" "shared" "container"];
};
```

### Namespaces

Every module receives a `namespace` argument. Options declared under
`config.<namespace>.*` stay separate from options in other modules:

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

### Shared lib

A `lib/` directory is available as `lib.<namespace>.*` in every module, package, shell,
and check:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

Access it with `lib.<namespace>.keys`, `lib.<namespace>.utils`, and so on.

### Packages

Packages under `packages/` become `packages.<system>.<name>`. They are also added to
`pkgs`, so other modules can refer to them directly:

```nix
# packages/hello/default.nix
{ lib, ... }: { /* ... */ }
```

```nix
# checks/lint/default.nix
{ pkgs, ... }: pkgs.hello   # the discovered package
```

Packages are wrapped the same way as `callPackage` packages, so `.override` and
`.overrideAttrs` work. They can depend on each other; mutual recursion is an error, as
in any nixpkgs overlay. To keep packages out of `pkgs`, set `packagesToPkgs = false`.
They remain available under `packages.<system>.<name>`. This applies to `mkFlake` and
the flake-parts module.

### Systems and homes

Systems and homes are discovered from `<arch>-<format>/<name>`:

```
systems/
├── x86_64-linux/server/default.nix    → nixosConfigurations.server
└── aarch64-darwin/macbook/default.nix → darwinConfigurations.macbook

homes/
└── x86_64-linux/alice@server/default.nix  → homeConfigurations."alice@server"
```

Host metadata can live in a `meta.nix` next to `default.nix`, or in `hosts.<name>.meta`
in the flake config. Setting `images` turns the host into an image-only recipe, useful
for installer ISOs. Such a host is left out of `nixosConfigurations` and
`darwinConfigurations` unless you also set `deployable = true`. Its images are exposed
as `images.<host>.<format>`:

```nix
# systems/x86_64-linux/installer/meta.nix
{
  images = [ "iso" ];
}
```

The merged metadata is passed to the host's modules as `purr.meta`.

A home named `<user>@<host>` links to the matching host automatically.

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.meta.name;  # "server"
  # home-manager config for alice@server is injected automatically
}
```

### Namespace bridge

A NixOS module can configure a linked home through `purr.users.<name>.homeConfig`:

```nix
{ config, pkgs, lib, ... }:
{
  purr.users.alice.homeConfig = {
    home.packages = [ pkgs.cowsay ];
    programs.git.userName = "Alice";
  };
}
```

## Why purr?

- One dependency, `nixpkgs-lib`.
- A single `mkFlake` call, or one flake-parts module.
- `namespace` injection without manual prefixes.
- Systems and homes discovered from the layout and linked automatically.
- A shared lib under `lib.<namespace>.*`.

## Testing

Tests live in `tests/` and are discovered automatically. Add a `test-*.nix` file under
`tests/unit/` for a `lib/` module, or under `tests/integration/` for a real project run
against `tests/integration/project`.

```bash
nix flake check                       # CI gate: pre-commit + purr-tests
nix build .#checks.x86_64-linux.purr-tests && cat result   # full per-test report
tests/run-tests.sh                    # run directly, live per-test output
nix develop --command purr-test       # same, from the dev shell
```

The `purr-tests` check writes the full report to `result`. If a test fails, the build
fails and `nix log` shows the failing cases. Unit tests run with `nixpkgs-lib`.
Integration tests mock `nixosSystem` and `homeManagerConfiguration` and evaluate the
generated configs through the real `lib.evalModules`, without a full nixpkgs.

## Documentation

More documentation is at [purr.nixcafe.org](https://purr.nixcafe.org): flake-parts
integration, the API reference, the directory layout guide, and more.

## License

[CC0 1.0 Universal](LICENSE)
