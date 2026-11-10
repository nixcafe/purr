# Module System

purr discovers modules from the directory layout and exports them as flake module
outputs. Modules are plain Nix modules; purr supplies the namespace and the project
lib.

## Module discovery

Place modules under `modules/`. The path below the module type directory becomes the
attribute path:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → nixos + darwin (shared)
```

### Module types

The default mapping decides which subdirectories go to which flake outputs:

| Output | Directories |
|--------|-------------|
| `nixosModules` | `nixos/`, `shared/` |
| `darwinModules` | `darwin/`, `shared/` |
| `homeModules` | `home/` |

Change it with `moduleTypes`:

```nix
moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

A directory is included only if it exists. Modules from all listed directories are
merged into the same output tree.

## Namespace

When `namespace` is set, each module receives it as a parameter. Options stay under
`config.<namespace>.*`:

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

The namespace wrapper also injects the defining flake's `inputs` and the merged lib,
so modules can use `lib.<namespace>.*` without an extra import.

## Module arguments

Auto-discovered modules receive different arguments depending on their directory:

| Directory | Arguments |
|-----------|-----------|
| `lib/` | `{ lib, inputs, namespace }` |
| `modules/` | `{ config, options, lib, pkgs, namespace, ... }` |
| `packages/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `legacyPackages/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `shells/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `checks/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `apps/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `formatters/` or `formatter/` | `{ inputs, system, namespace, lib, pkgs, ... }` |
| `overlays/` | `final: prev:` |
| `templates/` | `{ inputs, namespace, lib, ... }` |
| `systems/` | `{ config, options, lib, pkgs, purr, host, namespace, system, inputs, ... }` |
| `homes/` | `{ config, options, lib, pkgs, purr, user, host, namespace, system, inputs, ... }` |

`lib` in `packages/`, `legacyPackages/`, `shells/`, `checks/`, `apps/`, and
`formatters/` is the merged lib, including the project lib under
`lib.<namespace>.*`. `systems/` and `homes/` receive `purr` through `specialArgs`
and `extraSpecialArgs`. See [Systems & Homes](/systems-homes#purr-metadata) for the
shape of `purr`.

Discovered packages are registered in `pkgs` by default (`packagesToPkgs = true`) and
the whole `pkgs` set is passed to per-system modules. A package can therefore depend
on a sibling package by name: `{ hello, ... }: hello.override { ... }`. This applies
to per-system modules, not to NixOS or home modules, which use `pkgs.<name>`. See
[Packages](/mkflake#packages).

## Custom lib

Create a `lib/` directory under `src` to share functions across modules:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  keys = import ./keys.nix { inherit lib inputs namespace; };
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

The functions are available as `lib.<namespace>.*` in modules, packages, shells,
checks, apps, templates, formatters, and legacy packages:

```nix
# packages/known-hosts/default.nix
{ pkgs, lib, namespace, ... }:
let
  inherit (lib.${namespace}) keys;
in
pkgs.writeText "known-hosts" (keys.generate { ... })
```

Subdirectories nest by default (`lib.<namespace>.keys.foo`). Set `flattenLib = true`
to merge all submodules directly under the namespace (`lib.<namespace>.foo`). When
`namespace` is `null`, the lib is merged at the top level of `lib`.

A root `lib/default.nix` and subdirectory modules can coexist. The root module is
imported separately by `buildImportedPurrLib`; subdirectory modules are collected by
`findModulesLib`.

## Default module bundle

A `default` module that imports all discovered sub-modules is generated for
`nixosModules`, `darwinModules`, and `homeModules`. It is skipped when a discovered
module set or `extraModules` already defines `default`:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

`bundleModules` (default `false`) controls whether `extraModules` are folded into the
bundle. Set `bundleModules = true` to include them, and `bundleExtraModules = false`
to bundle only the auto-discovered modules.

## Extra modules

Inject modules from other flakes:

```nix
extraModules = {
  nixos = [
    inputs.my-extra-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```
