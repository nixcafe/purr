<h1 align="center">purr</h1>
<p align="center">
  A lean Nix flake framework — <strong>auto-discovery, namespaces, and module composition</strong>.
  <br />
  <a href="https://purr.nixcafe.org"><strong>purr.nixcafe.org</strong></a>
</p>

<p align="center">
  <a href="https://flakehub.com/flake/nixcafe/purr"><img src="https://img.shields.io/badge/FlakeHub-nixcafe%2Fpurr-blue?logo=nixos" alt="FlakeHub" /></a>
  <a href="https://github.com/nixcafe/purr/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-CC0--1.0-brightgreen" alt="License" /></a>
</p>

---

## What is purr?

purr turns your project directory structure into a fully wired Nix flake — **no boilerplate, no manual wiring**. Drop files into conventional directories and purr discovers everything: modules, packages, shells, checks, apps, overlays, templates, NixOS/darwin systems, home-manager homes, and a shared lib.

Compared to other flake auto-discovery tools, purr stays **minimal** — a single dependency (`nixpkgs-lib`, ~2 MB) and a small, focused API surface.

```nix
# flake.nix — that's it. No manual wiring needed.
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

Put your code in the right directories, and purr wires your entire flake:

```
.
├── flake.nix
├── modules/              → nixosModules, darwinModules, homeModules
├── packages/             → packages.<system>.*
├── shells/               → devShells.<system>.*
├── checks/               → checks.<system>.*
├── apps/                 → apps.<system>.*
├── overlays/             → overlays.*
├── templates/            → templates.*
├── lib/                  → lib.<namespace>.* (shared across all modules)
├── systems/              → nixosConfigurations, darwinConfigurations
└── homes/                → homeConfigurations
```

## Quick Start

Scaffold a new purr project in seconds:

```bash
# Standalone (mkFlake)
nix flake init -t github:nixcafe/purr

# With flake-parts
nix flake init -t github:nixcafe/purr#flake-parts
```

## Usage

purr offers two integration modes — pick the one that fits your workflow.

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

Customize the mapping with `moduleTypes`:

```nix
moduleTypes = {
  nixos = ["nixos" "shared" "container"];
};
```

### Namespace Support

purr injects a `namespace` parameter into every module, scoping options under `config.<namespace>.*` — no more global option collisions:

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

Create a `lib/` directory to share functions across all modules, packages, shells, and checks:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

Access anywhere with `lib.<namespace>.keys`, `lib.<namespace>.utils`, etc.

### Systems & Homes

purr auto-discovers NixOS/darwin systems and home-manager homes using `<arch>-<format>/<name>`:

```
systems/
├── x86_64-linux/server/default.nix    → nixosConfigurations.server
├── aarch64-darwin/macbook/default.nix → darwinConfigurations.macbook
└── x86_64-iso/server/default.nix      → isoConfigurations.server

homes/
└── x86_64-linux/alice@server/default.nix  → homeConfigurations."alice@server"
```

Homes named `<user>@<host>` auto-link to matching hosts. No extra wiring needed.

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.name;  # "server"
  # ...auto-injects home-manager config for alice@server automatically
}
```

### Namespace Bridge

Forward home-manager config from any NixOS module via the namespace bridge:

```nix
{ config, pkgs, lib, namespace, ... }:
{
  ${namespace}.users.alice.homeConfig = {
    home.packages = [ pkgs.cowsay ];
    programs.git.userName = "Alice";
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

## Testing

Tests live under `tests/` and are auto-discovered — drop a
`test-*.nix` into `tests/unit/` (1:1 with a `lib/` module) or
`tests/integration/` (real-project runs against `tests/integration/project`)
and it is picked up automatically.

```bash
nix flake check                       # CI gate: pre-commit + purr-tests
nix build .#checks.x86_64-linux.purr-tests && cat result   # full per-test report
tests/run-tests.sh                    # run directly, live per-test output
nix develop --command purr-test       # same, from the dev shell
```

The `purr-tests` check writes the full report into its `result`; if a test
fails the build fails and `nix log` shows the failing cases. Unit tests run
hermetically with `nixpkgs-lib`; integration tests mock `nixosSystem` /
`homeManagerConfiguration` to evaluate the generated configs through the real
`lib.evalModules` without pulling a full nixpkgs.

## Documentation

Full documentation at **[purr.nixcafe.org](https://purr.nixcafe.org)** — flake-parts integration, full API reference, directory layout guide, and more.

## License

[CC0 1.0 Universal](LICENSE)
