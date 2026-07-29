# mkFlake Usage

`mkFlake` is purr's standalone flake builder. Use it when you don't need or want flake-parts.

## Basic Usage

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

## Full API Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `inputs` | attrs | *required* | Flake inputs. Required: `nixpkgs`. Optional: `home-manager` (or `homeManager`) for home-manager support, `nix-darwin` (or `darwin`) for darwin support |
| `src` | path | *required* | Project root directory |
| `namespace` | nullOr str | `null` | Module option namespace, also used as lib key (`lib.<namespace>`) |
| `libDir` | nullOr str | `null` | Lib directory (relative to `src`), auto-detects `lib/` |
| `flattenLib` | bool | `false` | Flatten lib subdirectories into root (no dir nesting) |
| `systems` | list | `["x86_64-linux" "aarch64-linux" "aarch64-darwin"]` | Systems to generate for |
| `nixpkgsConfig` | attrs | `{}` | nixpkgs config (`allowUnfree`, etc.) |
| `outputsBuilder` | fn | `({ pkgs, system, inputs, namespace, lib, ... }: {})` | Per-system extra flake outputs. Also receives all `extraArgs` keys |
| `modulesDir` | str | `"modules"` | Module directory name under src |
| `moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | Subdirectory mapping per output |
| `extraModules` | attrs | `{}` | `{nixos=[...]; darwin=[...]; home=[...]}` — raw module injection |
| `extraArgs` | attrs | `{}` | Custom key-value pairs injected into all auto-discovered module args (packages, shells, checks, apps, templates, system `specialArgs`, home `extraSpecialArgs`). Purr's own keys override `extraArgs` on conflict |
| `bundleModules` | bool | `false` | Bundle all modules into a `default` module |
| `bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle |
| `checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `packagesByName` | bool | `false` | Also discover packages via `by-name/` convention (coexists with regular discovery) |
| `appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `homesDir` | nullOr str | `null` | auto-detects `homes/` |
| `autoInject` | bool | `true` | Auto-inject `networking.hostName`, `home.username`, etc. |

## Customizing Systems

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systems = [ "x86_64-linux" "aarch64-linux" ];
}
```

## Custom Module Directories

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  moduleTypes = {
    nixos = ["nixos" "shared" "container"];
  };
}
```

## Systems & Homes

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systemsDir = "systems";   # or "hosts", or null to auto-detect
  homesDir = "homes";
}
```

## Extra Args

Pass custom values to every auto-discovered module:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  extraArgs = {
    deploymentTarget = "production";
  };
}
```

Modules receive `extraArgs` values as function parameters:

```nix
# packages/myapp/default.nix
{ deploymentTarget, pkgs, ... }:
pkgs.writeText "myapp" "target: ${deploymentTarget}"
```

All auto-discovered modules receive `extraArgs` keys — packages, shells, checks, apps, templates, system `specialArgs`, home `extraSpecialArgs`, and `outputsBuilder`. Purr's own keys (`inputs`, `pkgs`, `namespace`, `lib`, etc.) always override `extraArgs` in case of naming conflicts.
