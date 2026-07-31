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
| `outputsBuilder` | fn | `({ pkgs, system, inputs, namespace, lib, ... }: {})` | Per-system extra flake outputs. Also receives all `extraArgs` keys. Results are **deep-merged** with auto-discovered outputs, so both coexist (e.g. `packages` from auto-discovery and from `outputsBuilder`) |
| `modulesDir` | str | `"modules"` | Module directory name under src |
| `moduleTypes` | attrs | `{nixos=["nixos" "shared"]; ...}` | Subdirectory mapping per output |
| `extraModules` | attrs | `{}` | `{nixos=[...]; darwin=[...]; home=[...]}` — raw module injection |
| `extraArgs` | attrs | `{}` | Custom key-value pairs injected into all auto-discovered module args (packages, shells, checks, apps, templates, system `specialArgs`, home `extraSpecialArgs`). Purr's own keys override `extraArgs` on conflict |
| `bundleModules` | bool | `false` | Include `extraModules` in the auto-generated `default` bundle (the `default` module itself is always generated unless you define your own) |
| `bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle (only when `bundleModules = true`) |
| `checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `packagesByName` | bool | `false` | Also discover packages via `by-name/` convention (coexists with regular discovery) |
| `legacyPackagesDir` | nullOr str | `null` | auto-detects `legacyPackages/` |
| `legacyPackagesByName` | bool | `false` | Also discover legacy packages via `by-name/` convention (coexists with regular discovery) |
| `appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `formatterDir` | nullOr str | `null` | auto-detects `formatters/` then `formatter/`. The `default.nix` must return a derivation (`{ pkgs, ... }: pkgs.nixfmt-rfc-style`) |
| `systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `homesDir` | nullOr str | `null` | auto-detects `homes/` |
| `autoInject` | bool | `true` | Auto-inject `networking.hostName`, `home.username`, etc. |
| `hydraJobs` | attrs | `{}` | Hydra CI options: `{ enable, dir, systems, include, extra }`. See below |

## Hydra CI (hydraJobs)

Generate a `hydraJobs` output for Hydra CI that automatically mirrors every buildable output, plus custom jobs from a `hydraJobs/` directory:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hydraJobs = {
    enable = true;
    systems = ["x86_64-linux"];
    include = [ "checks" "packages" "nixosConfigs" ];
  };
}
```

See the [hydraJobs](/hydrajobs) page for the full reference.

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

## Formatter

Auto-discover a per-system formatter from `formatters/` (or `formatter/`). The `default.nix` receives `{ pkgs, lib, system, namespace, inputs, ... }` and must return a derivation:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style
```

This produces `formatter.<system>` so `nix fmt` works out of the box. You can still override via `outputsBuilder`:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  outputsBuilder = { pkgs, ... }: {
    formatter = pkgs.alejandra;
  };
}
```

## Legacy Packages

Auto-discover `legacyPackages.<system>.*` from `legacyPackages/` — the convention for unmergeable or non-standard packages, still buildable via `nix build .#<name>`:

```nix
# legacyPackages/hello/default.nix
{ pkgs, ... }: pkgs.hello
```

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  legacyPackagesByName = true;   # also scan legacyPackages/by-name/<shard>/<name>/package.nix
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
