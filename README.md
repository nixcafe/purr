# Purr

Purr — a lean Nix flake library for module auto-discovery and namespace
support. Compared to other flake module auto-discovery tools, Purr stays
minimal with a single dependency and a smaller default surface area.

## Why Purr?

- **Minimal footprint** — single dependency (`nixpkgs-lib`, ~2MB)
- **Auto-discovery** — recursively scans `modules/{nixos,darwin,home,shared}/` for modules
- **Namespace support** — injects `namespace` into every module, keeping options under `config.<namespace>.*`
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
      outputsBuilder = { pkgs }: {
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
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.purr.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      purr = {
        enable = true;
        src = ./.;
        namespace = "cattery";
      };
    };
}
```

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

## API

### `mkFlake`

| Parameter | Type | Default | |
|-----------|------|---------|---|
| `inputs` | attrs | *required* | Flake inputs (must include nixpkgs) |
| `src` | path | *required* | Project root directory |
| `namespace` | nullOr str | `null` | Module option namespace |
| `libDir` | nullOr str | `null` | Lib directory (relative to `src`), injected as `lib.<namespace>` |
| `systems` | list | `["x86_64-linux" "aarch64-linux" "aarch64-darwin"]` | Systems to generate for |
| `channelsConfig` | attrs | `{}` | nixpkgs config (allowUnfree, etc.) |
| `outputsBuilder` | fn | `({ pkgs, system }: {})` | Per-system extra flake outputs (formatter, packages, etc.) |
| `modulesDir` | str | `"modules"` | Module directory name under src |
| `moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | Subdirectory mapping per output |
| `extraModules` | attrs | `{}` | `{nixos=[...]; darwin=[...]; home=[...]}` — raw module injection |
| `checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |

### flake-parts Options

| Option | Type | Default | |
|--------|------|---------|---|
| `purr.enable` | bool | `false` | |
| `purr.src` | path | *required* | Project root |
| `purr.namespace` | nullOr str | `null` | |
| `purr.libDir` | nullOr str | `null` | Lib directory (relative to `src`) |
| `purr.modulesDir` | str | `"modules"` | |
| `purr.moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | |
| `purr.checksDir` | nullOr str | `null` | auto-detects |
| `purr.shellsDir` | nullOr str | `null` | auto-detects |
| `purr.overlaysDir` | nullOr str | `null` | auto-detects |

### Helpers

```nix
inputs.purr.lib.defaultSystems  # ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
inputs.purr.lib.eachSystem [...]
inputs.purr.lib.eachDefaultSystem
inputs.purr.lib.collectModules  # flatten nested modules to a list
inputs.purr.lib.loadModules     # recursively load .nix files from a dir
```

## License

CC0 1.0 Universal
