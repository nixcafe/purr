# Module System

purr auto-discovers modules from your directory structure and wires them into your flake outputs.

## Module Discovery

Place modules under `modules/` and they're auto-discovered:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → nixos + darwin (shared)
```

### Module Types

The default module type mapping determines which subdirectories go to which flake outputs:

| Output | Directories |
|--------|-------------|
| `nixosModules` | `nixos/`, `shared/` |
| `darwinModules` | `darwin/`, `shared/` |
| `homeModules` | `home/` |

Customize with `moduleTypes`:

```nix
moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

## Namespace

Each module receives `namespace` as a parameter, keeping options scoped under `config.<namespace>.*`:

```nix
{ config, lib, namespace, ... }@args:
let
  cfg = config.${namespace}.my-module;
in
{
  options.${namespace}.my-module.enable = lib.mkEnableOption "my module";
  config = lib.mkIf cfg.enable { ... };
}
```

## Module Arguments

Each auto-discovered module receives different arguments depending on its directory:

| Directory | Arguments |
|-----------|-----------|
| `lib/` | `{ lib, inputs, namespace }` |
| `modules/` | `{ config, options, lib, pkgs, namespace, ... }` |
| `packages/` | `{ inputs, system, namespace, lib, pkgs }` |
| `legacyPackages/` | `{ inputs, system, namespace, lib, pkgs }` |
| `shells/` | `{ inputs, system, namespace, lib, pkgs }` |
| `checks/` | `{ inputs, system, namespace, lib, pkgs }` |
| `apps/` | `{ inputs, system, namespace, lib, pkgs }` |
| `formatter/` | `{ inputs, system, namespace, lib, pkgs }` |
| `overlays/` | `final: prev:` (Nix overlay convention) |
| `templates/` | `{ inputs, namespace, lib }` |
| `systems/` | `{ config, options, lib, pkgs, purr, host, namespace, system, inputs, ... }` |
| `homes/` | `{ config, options, lib, pkgs, purr, purrLib, host, namespace, system, inputs, ... }` |

> **Note:** `lib` in `packages/`, `legacyPackages/`, `shells/`, `checks/`, `apps/`, and `formatter/` includes the project's custom lib under `lib.<namespace>.*`, merged via `purrLib`. `systems/` and `homes/` receive a `purr` attrset with metadata about the current configuration context via `specialArgs` / `extraSpecialArgs`.

## Custom Lib

Create a `lib/` directory under `src` to share functions across all modules:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

Functions are accessible as `lib.<namespace>.*` in all modules, packages, shells, and checks:

```nix
# packages/known-hosts/default.nix
{ pkgs, lib, namespace, ... }:
let
  inherit (lib.${namespace}) keys;
in
pkgs.writeText "known-hosts" (keys.generate { ... })
```

Subdirectories nest by default (`lib.<namespace>.keys.foo`). Set `flattenLib = true` to merge all submodules directly under the namespace (`lib.<namespace>.foo`).

The `lib/` directory supports both a root `default.nix` and recursive subdirectory discovery via `findModules` — both can coexist.

## Default Module Bundle

A `default` module that imports all discovered sub-modules is **always generated** (for `nixosModules`, `darwinModules`, and `homeModules`) — unless you define your own `default` module, in which case the auto-generated bundle is skipped:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

`bundleModules` (default `false`) controls whether your `extraModules` are folded into this bundle. Set `bundleModules = true` to include them; combine with `bundleExtraModules = false` to include only the auto-discovered modules.

## Extra Modules

Inject modules from other flakes:

```nix
extraModules = {
  nixos = [
    inputs.cattery-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```
