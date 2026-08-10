# purr

purr turns your project directory structure into a fully wired Nix flake — **no boilerplate, no manual wiring**. Drop files into conventional directories and purr discovers everything: modules, packages, legacy packages, shells, checks, apps, overlays, templates, a formatter, NixOS/darwin systems, home-manager homes, and a shared lib.

Compared to other flake auto-discovery tools, purr stays **minimal** — a single dependency (`nixpkgs-lib`, ~2 MB) and a small, focused API surface.

***

## Quick Start

Scaffold a new purr project in seconds:

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

## Why purr?

| | purr | Other frameworks |
|---|---|---|
| **Dependencies** | 1 (`nixpkgs-lib`, ~2 MB) | 3+ (flake-parts, flake-utils, ...) |
| **API surface** | Single `mkFlake` call or one flake-parts module | Multiple nested imports |
| **Option namespace** | Built-in `namespace` injection | Manual `config.<name>.` prefixing |
| **Systems & homes** | Auto-discovered, auto-linked | Manual wiring |
| **Custom lib** | `lib.<namespace>.*` propagated everywhere | Manual import passthrough |

## Core Concepts

### Automatic Module Discovery

Drop modules into `modules/` — purr discovers them by subdirectory convention:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → merged into nixos + darwin
```

### Namespace Support

purr injects a `namespace` parameter into every module:

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

### Custom Lib (`lib.<namespace>.*`)

Share functions across all modules via a `lib/` directory:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

Access anywhere as `lib.<namespace>.keys`, `lib.<namespace>.utils`.

### Systems & Homes

Auto-discover NixOS/darwin systems and home-manager homes:

```
systems/
├── x86_64-linux/server/default.nix    → nixosConfigurations.server
└── homes/
    └── x86_64-linux/alice@server/     → homeConfigurations."alice@server"
                                        (auto-linked to server)
```

See the [Systems & Homes](/systems-homes) page for the namespace bridge and image formats, and the [Host Meta](/meta) page for per-host metadata (`meta.nix`, `hosts.<name>.meta`, `purr.meta`).

### hydraJobs (CI)

Generate a `hydraJobs` output for Hydra CI that automatically mirrors every buildable output — packages, checks, shells, NixOS/hosts toplevels, home activation packages, and system images — plus custom jobs from a `hydraJobs/` directory. See the [hydraJobs](/hydrajobs) page.

## Integration Modes

purr works in two modes — pick whichever fits your stack:

* **[flake-parts](/flake-parts)** — use as a flake-parts module alongside other frameworks
* **[mkFlake](/mkflake)** — standalone, no flake-parts dependency needed

## Project Structure

See the [Directory Structure](/directory-structure) page for the complete layout — purr auto-detects everything from modules to overlays, templates to apps.

## API Reference

The full library API (42 functions) is documented on the [API Reference](/api) page.
