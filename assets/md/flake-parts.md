# flake-parts Integration

purr works as a [flake-parts](https://github.com/hercules-ci/flake-parts) module, giving you access to all purr features alongside other flake-parts modules.

## Setup

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

## Options

All options are under the `purr.*` namespace.

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.enable` | bool | `false` | Enable purr |
| `purr.src` | path | *required* | Project root directory |
| `purr.namespace` | nullOr str | `null` | Module option namespace |
| `purr.libDir` | nullOr str | `null` | auto-detects `lib/` |
| `purr.flattenLib` | bool | `false` | Flatten lib subdirectories into root |
| `purr.modulesDir` | str | `"modules"` | Module directory name under src |
| `purr.moduleTypes` | attrs | See below | Subdirectory mapping per output |
| `purr.extraModules` | attrs | `{}` | `{ nixos = [...]; darwin = [...]; home = [...]; }` |
| `purr.extraArgs` | attrs | `{}` | Custom key-value pairs injected into all auto-discovered module args (packages, shells, checks, apps, templates, system `specialArgs`, home `extraSpecialArgs`). Purr's own keys override `extraArgs` on conflict |
| `purr.bundleModules` | bool | `false` | Bundle all modules into a `default` module |
| `purr.bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle |

Default `moduleTypes`:

```nix
{
  nixos = ["nixos" "shared"];
  darwin = ["darwin" "shared"];
  home = ["home"];
}
```

### Directory Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `purr.shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `purr.overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `purr.packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `purr.packagesByName` | bool | `false` | Also discover packages via `by-name/` convention (coexists with regular discovery) |
| `purr.legacyPackagesDir` | nullOr str | `null` | auto-detects `legacyPackages/` |
| `purr.legacyPackagesByName` | bool | `false` | Also discover legacy packages via `by-name/` convention (coexists with regular discovery) |
| `purr.appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `purr.templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `purr.templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `purr.formatterDir` | nullOr str | `null` | auto-detects `formatters/` then `formatter/`. The `default.nix` must return a derivation |
| `purr.systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `purr.homesDir` | nullOr str | `null` | auto-detects `homes/` |

### Other Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.nixpkgsConfig` | attrs | `{}` | nixpkgs config (`allowUnfree`, etc.) |
| `purr.autoInject` | bool | `true` | Auto-inject `networking.hostName`, `home.username`, etc. |
| `purr.outputsBuilder` | fn | `(_: {})` | Additional per-system outputs. Called for each system with `{ pkgs, system, lib, inputs, namespace }` plus all `extraArgs` keys; the returned attrset is **deep-merged** into the perSystem flake outputs |

### hydraJobs Options

All under `purr.hydraJobs.*`. See the [hydraJobs](/hydrajobs) page for details.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.hydraJobs.enable` | bool | `false` | Enable the `hydraJobs` flake output |
| `purr.hydraJobs.dir` | nullOr str | `null` | Custom jobs directory, auto-detects `hydraJobs/` |
| `purr.hydraJobs.systems` | nullOr \[str] | `null` | Filter which systems get CI jobs |
| `purr.hydraJobs.include` | nullOr \[str] | `null` | Mirror outputs into hydraJobs (`null` = auto-detect all) |
| `purr.hydraJobs.extra` | attrs | `{}` | Extra jobs merged last, highest priority |

## Custom Module Directories

You can customize which subdirectories are scanned for each module type:

```nix
purr.moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

## Extra Modules from Other Flakes

Inject external modules alongside auto-discovered ones:

```nix
purr.extraModules = {
  nixos = [
    inputs.cattery-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```

## Default Module Bundle

A `default` module that imports all discovered sub-modules is **always generated** (for `nixosModules`, `darwinModules`, and `homeModules`) — unless you define your own `default` module, in which case the auto-generated bundle is skipped. Users can import with:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

`bundleModules` (default `false`) controls whether your `extraModules` are folded into this bundle. Set `bundleModules = true` to include them; combine with `bundleExtraModules = false` to include only the auto-discovered modules.

```nix
purr.bundleModules = true;        # include extraModules in the default bundle
purr.bundleExtraModules = false;  # (optional) only discovered modules, no extras
```

## Formatter & Legacy Packages

Auto-discovery works the same as mkFlake — drop a `formatters/default.nix` (returns a derivation) or `legacyPackages/<name>/default.nix` and the outputs appear:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style

# legacyPackages/hello/default.nix
{ pkgs, ... }: pkgs.hello
```

To also scan the `by-name/` convention for legacy packages, enable `legacyPackagesByName`:

```nix
purr.legacyPackagesByName = true;   # also scan legacyPackages/by-name/
```

## Outputs Builder

`purr.outputsBuilder` mirrors mkFlake's `outputsBuilder` — add any custom per-system output. It receives `{ pkgs, system, lib, inputs, namespace }` plus all `extraArgs` keys, and its result is deep-merged with purr's auto-discovered outputs:

```nix
purr.outputsBuilder = { pkgs, system, lib, namespace, ... }: {
  packages.fmt = pkgs.nixfmt-rfc-style;
};
```

## Hydra CI (hydraJobs)

Generate a `hydraJobs` output for Hydra that automatically mirrors every buildable output and adds custom jobs from a `hydraJobs/` directory:

```nix
purr.hydraJobs = {
  enable = true;
  systems = ["x86_64-linux"];
  include = [ "checks" "packages" "nixosConfigs" ];
};
```

See the [hydraJobs](/hydrajobs) page for the full reference.

## Namespace Lib Output

When a `lib/` directory exists and `namespace` is set, purr exports the namespace lib as a flake `lib.<namespace>` output — in both mkFlake and flake-parts modes:

```nix
# lib/default.nix
{ lib, inputs, namespace }:
{
  utils = import ./utils.nix { inherit lib inputs namespace; };
}
```

```bash
nix eval .#lib.myproject.utils
```

## Extra Args

Pass custom values to every auto-discovered module:

```nix
purr.extraArgs = {
  deploymentTarget = "production";
};
```

Modules receive `extraArgs` values as function parameters:

```nix
# modules/nixos/server/default.nix
{ deploymentTarget, config, lib, ... }:
{
  services.nginx.virtualHosts."myapp" = lib.mkIf (deploymentTarget == "production") {
    # ...
  };
}
```

All auto-discovered modules receive `extraArgs` keys — packages, shells, checks, apps, templates, system `specialArgs`, home `extraSpecialArgs`, and `outputsBuilder`. Purr's own keys (`inputs`, `pkgs`, `namespace`, `lib`, etc.) always override `extraArgs` in case of naming conflicts.
