# Purr

Purr — a lean Nix flake library for module auto-discovery and namespace
support. Compared to other flake module auto-discovery tools, Purr stays
minimal with a single dependency and a smaller default surface area.

## Why Purr?

- **Minimal footprint** — single dependency (`nixpkgs-lib`, ~2MB)
- **Auto-discovery** — recursively scans directories for modules, packages, shells, checks, apps, overlays, templates, and lib
- **Namespace support** — injects `namespace` into every module, keeping options under `config.<namespace>.*`
- **Lib propagation** — project custom lib (`lib.<namespace>.*`) available to all auto-discovered modules
- **Dual integration** — works standalone via `mkFlake` or as a flake-parts module

## Usage

### Standalone (mkFlake)

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

### flake-parts

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purr.url = "github:nixcafe/purr";
    my-extra-modules.url = "github:user/my-extra-modules";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.purr.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      purr = {
        enable = true;
        src = ./.;
        namespace = "cattery";
        extraModules.nixos = [
          inputs.my-extra-modules.nixosModules.default
        ];
      };
    };
}
```

## Directory Structure

All directories are auto-detected under `src`:

```
src/
├── lib/                              # Project library (auto-detect: "lib")
│   ├── default.nix                   #   import { lib }: returns attrset
│   ├── keys/
│   │   └── default.nix               #   → lib.<namespace>.keys
│   └── utils/
│       └── default.nix               #   → lib.<namespace>.utils
│
├── modules/                          # NixOS/darwin/home modules
│   ├── nixos/                        #   → nixosModules
│   ├── darwin/                       #   → darwinModules
│   ├── home/                         #   → homeModules
│   └── shared/                       #   → merged into nixos + darwin
│
├── packages/                         # Per-system packages (auto-detect: "packages")
│   ├── known-hosts/
│   │   └── default.nix               #   → packages.<system>.known-hosts
│   └── match-blocks/
│       └── default.nix               #   → packages.<system>.match-blocks
│
├── shells/                           # Dev shells (auto-detect: "shells", "devShells")
│   └── default/
│       └── default.nix               #   → devShells.<system>.default
│
├── checks/                           # Per-system checks (auto-detect: "checks")
│   └── pre-commit/
│       └── default.nix               #   → checks.<system>.pre-commit
│
├── overlays/                         # Overlays (auto-detect: "overlays")
│   └── custom/
│       └── default.nix               #   → overlays.custom
│
├── templates/                        # Flake templates (auto-detect: "templates")
│   └── rust/                         #   non-recursive by default
│       └── default.nix               #   → templates.rust
│
└── apps/                             # Per-system apps (auto-detect: "apps")
    └── serve/
        └── default.nix               #   → apps.<system>.serve
```

### Module arguments

Each auto-discovered module receives different arguments:

| Directory | Arguments |
|---|---|
| `lib/` | `{ lib }` |
| `modules/` | `{ config, options, lib, pkgs, namespace, ... }` |
| `packages/` | `{ inputs, system, namespace, lib, pkgs }` |
| `shells/` | `{ inputs, system, namespace, lib, pkgs }` |
| `checks/` | `{ inputs, system, namespace, lib, pkgs }` |
| `apps/` | `{ inputs, system, namespace, lib, pkgs }` |
| `overlays/` | `final: prev:` (Nix overlay convention) |
| `templates/` | `{ inputs, namespace, lib }` |

> **Note:** `lib` in `packages/`, `shells/`, `checks/`, and `apps/` includes the
> project's custom lib under `lib.<namespace>.*`, merged via `purrLib`.

## Module Discovery

Place modules under `modules/` and they're auto-discovered:

```
modules/
├── nixos/services/openssh/default.nix  → nixosModules.services.openssh
├── darwin/system/defaults/default.nix  → darwinModules.system.defaults
├── home/programs/git/default.nix       → homeModules.programs.git
└── shared/users/default.nix            → nixos + darwin (shared)
```

Each module receives `namespace` as a parameter:

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

## Custom Lib

Create a `lib/` directory under `src` to share functions across all modules:

```nix
# lib/default.nix
{ lib }:
{
  keys = import ./keys.nix { inherit lib; };
  utils = import ./utils.nix { inherit lib; };
}
```

Functions are accessible as `lib.<namespace>.*` in all modules, packages,
shells, and checks:

```nix
# packages/known-hosts/default.nix
{ pkgs, lib, namespace, ... }:
let
  inherit (lib.${namespace}) keys;
in
pkgs.writeText "known-hosts" (keys.generate { ... })
```

The `lib/` directory supports both a root `default.nix` and recursive
subdirectory discovery via `findModules` — both can coexist.

### Custom module directories

```nix
moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

### Extra modules from other flakes

```nix
extraModules = {
  nixos = [
    inputs.cattery-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```

### Default module bundle

By default, sub-modules are exported individually. Enable `bundleModules = true`
to auto-generate a `default` module that imports all sub-modules:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

Set `bundleExtraModules = false` to exclude extraModules from the default
bundle (only auto-discovered modules will be included). If you define your own
`default` module under `modules/`, the auto-generated bundle is skipped.

## Systems & Homes

Purr auto-discovers NixOS/darwin systems, home-manager homes, and image formats
using the `<arch>-<format>/<name>` convention (compatible with
[Snowfall Lib](https://snowfall.org)).

### Directory structure

```
src/
├── systems/                          # auto-detect: "systems", "hosts"
│   ├── x86_64-linux/
│   │   ├── server/default.nix        # → nixosConfigurations.server
│   │   └── laptop/default.nix        # → nixosConfigurations.laptop
│   ├── x86_64-iso/
│   │   └── server/default.nix        # → isoConfigurations.server
│   ├── x86_64-do/
│   │   └── server/default.nix        # → doConfigurations.server
│   └── aarch64-darwin/
│       └── macbook/default.nix       # → darwinConfigurations.macbook
│
├── homes/                            # auto-detect: "homes"
│   ├── x86_64-linux/
│   │   ├── alice@server/default.nix  # → homeConfigurations."alice@server"
│   │   └── bob@server/default.nix    # → homeConfigurations."bob@server"
│   └── aarch64-darwin/
│       └── alice@macbook/default.nix # → homeConfigurations."alice@macbook"
│
├── modules/
├── lib/
└── ...
```

### System output mapping

| Format in dir name | Flake output key | Builder |
|---|---|---|
| `linux` | `nixosConfigurations.<name>` | `nixosSystem` |
| `darwin` | `darwinConfigurations.<name>` | `darwinSystem` |
| `iso`, `do`, … | `<format>Configurations.<name>` | `nixosSystem` + `image.variant` |

### Home auto-linking

Homes named `<user>@<host>` are automatically injected into matching hosts.
When `home-manager` is available as an input, building `nixosConfigurations.server`
will include all homes with `@server` suffix:

```nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];
  programs.git.enable = true;
}
```

The home is auto-configured via `home-manager.users.alice` in the host's NixOS
config. No additional wiring needed.

### Image formats (nixos-generators replacement)

nixos-generators was merged into nixpkgs (25.05+). Set `image.variant` in the
system config to build images. Purr auto-detects format directories and adds
the variant:

```nix
# systems/x86_64-iso/server/default.nix
{ ... }: {
  image.variant = "iso";  # implied, auto-set by Purr
}
```

### Example usage

**mkFlake:**
```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systemsDir = "systems";   # or "hosts", or null to auto-detect
  homesDir = "homes";
}
```

**flake-parts:**
```nix
purr = {
  enable = true;
  src = ./.;
  systemsDir = "systems";
  homesDir = "homes";
}
```

## API

### `mkFlake`

| Parameter | Type | Default | |
|-----------|------|---------|---|
| `inputs` | attrs | *required* | Flake inputs (must include nixpkgs) |
| `src` | path | *required* | Project root directory |
| `namespace` | nullOr str | `null` | Module option namespace, also used as lib key (`lib.<namespace>`) |
| `libDir` | nullOr str | `null` | Lib directory (relative to `src`), auto-detects `lib/` |
| `systems` | list | `["x86_64-linux" "aarch64-linux" "aarch64-darwin"]` | Systems to generate for |
| `nixpkgsConfig` | attrs | `{}` | nixpkgs config (allowUnfree, etc.) |
| `outputsBuilder` | fn | `({ pkgs, system, inputs, namespace, lib }: {})` | Per-system extra flake outputs (formatter, packages, etc.) |
| `modulesDir` | str | `"modules"` | Module directory name under src |
| `moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | Subdirectory mapping per output |
| `extraModules` | attrs | `{}` | `{nixos=[...]; darwin=[...]; home=[...]}` — raw module injection |
| `bundleModules` | bool | `false` | Bundle all modules into a `default` module |
| `bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle |
| `checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `homesDir` | nullOr str | `null` | auto-detects `homes/` |

### flake-parts Options

| Option | Type | Default | |
|--------|------|---------|---|
| `purr.enable` | bool | `false` | |
| `purr.src` | path | *required* | Project root |
| `purr.namespace` | nullOr str | `null` | |
| `purr.libDir` | nullOr str | `null` | auto-detects `lib/` |
| `purr.modulesDir` | str | `"modules"` | |
| `purr.moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | |
| `purr.checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `purr.shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `purr.overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `purr.packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `purr.appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `purr.templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `purr.templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `purr.extraModules` | attrs | `{}` | `{nixos=[...]; darwin=[...]; home=[...]}` |
| `purr.bundleModules` | bool | `false` | Bundle all modules into a `default` module |
| `purr.bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle |
| `purr.systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `purr.homesDir` | nullOr str | `null` | auto-detects `homes/` |
| `purr.nixpkgsConfig` | attrs | `{}` | nixpkgs config (allowUnfree, etc.) |

```nix
inputs.purr.lib.defaultSystems  # ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
inputs.purr.lib.eachSystem [...]
inputs.purr.lib.eachDefaultSystem
inputs.purr.lib.collectModules  # flatten nested modules to a list
inputs.purr.lib.loadModules     # recursively load .nix files from a dir
```

## License

CC0 1.0 Universal
