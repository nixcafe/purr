# flake-parts Integration

purr provides a [flake-parts](https://github.com/hercules-ci/flake-parts) module at
`inputs.purr.flakeModules.default`. It adds the `purr.*` options and builds the
discovered flake outputs.

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

### Core options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.enable` | bool | `false` | Enable purr |
| `purr.src` | path | required | Project root directory |
| `purr.namespace` | nullOr str | `null` | Module option namespace |
| `purr.libDir` | nullOr str | `null` | Path under `src` for the project lib; auto-detects `lib/` |
| `purr.flattenLib` | bool | `false` | Flatten lib subdirectories into the namespace root |
| `purr.modulesDir` | str | `"modules"` | Module directory name under `src` |
| `purr.moduleTypes` | attrs | See below | Subdirectory mapping per output |
| `purr.extraModules` | attrs | `{}` | `{ nixos = [...]; darwin = [...]; home = [...]; }` |
| `purr.extraArgs` | attrs | `{}` | Custom values added to the arguments of every auto-discovered module, system `specialArgs`, and home `extraSpecialArgs`. purr's own keys win on conflict |
| `purr.bundleModules` | bool | `false` | Include `extraModules` in the generated `default` module bundle |
| `purr.bundleExtraModules` | bool | `true` | Include extra modules in the bundle when `bundleModules` is on |

Default `moduleTypes`:

```nix
{
  nixos = ["nixos" "shared"];
  darwin = ["darwin" "shared"];
  home = ["home"];
}
```

### Directory options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `purr.shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `purr.overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `purr.packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `purr.packagesByName` | bool | `false` | Also discover packages from `packages/by-name/<shard>/<name>/package.nix` |
| `purr.packagesToPkgs` | bool | `true` | Register discovered packages in `pkgs` as well. See [Packages](/mkflake#packages) |
| `purr.legacyPackagesDir` | nullOr str | `null` | auto-detects `legacyPackages/` |
| `purr.legacyPackagesByName` | bool | `false` | Also discover legacy packages from the `by-name/` layout |
| `purr.appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `purr.templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `purr.templatesRecursive` | bool | `false` | Scan `templates/` recursively |
| `purr.formatterDir` | nullOr str | `null` | auto-detects `formatters/` then `formatter/`. The `default.nix` must return a derivation |
| `purr.systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `purr.homesDir` | nullOr str | `null` | auto-detects `homes/` |

### Other options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.nixpkgsConfig` | attrs | `{}` | nixpkgs config such as `allowUnfree` |
| `purr.inputsFor` | nullOr fn | `null` | Filter or replace the flake inputs that purr uses internally. Accepts `{ inputs, ... } -> inputs'` or a plain attrset. Modules still receive the raw `inputs`. See [Per-host inputs](/mkflake#per-host-inputs-multi-nixpkgs) |
| `purr.autoInject` | bool | `true` | Inject `networking.hostName`, `home.username`, and `home.homeDirectory` with `lib.mkDefault` |
| `purr.outputsBuilder` | fn | `(_: {})` | Additional per-system outputs. Called with `{ pkgs, system, lib, inputs, namespace }` plus every `extraArgs` key. The result is deep-merged into the per-system outputs |
| `purr.hosts` | attrs | `{}` | Per-host config: `purr.hosts.<name>.meta = { images = [...]; deployable = true; roles.nixpkgs = "..."; ... }`, deep-merged over the host's `meta.nix`. See [Host Meta](/meta) |

### hydraJobs options

All under `purr.hydraJobs.*`. See the [hydraJobs](/hydrajobs) page for details.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.hydraJobs.enable` | bool | `false` | Enable the `hydraJobs` flake output |
| `purr.hydraJobs.as` | str | `"hydraJobs"` | Name of the flake output carrying the jobs |
| `purr.hydraJobs.dir` | nullOr str | `null` | Jobs directory; auto-detects `hydraJobs/` |
| `purr.hydraJobs.systems` | nullOr \[str] | `null` | Restrict CI jobs to these systems. Also restricts the top-level `images` output |
| `purr.hydraJobs.include` | nullOr \[str] | `null` | Outputs to mirror into hydraJobs; `null` auto-detects |
| `purr.hydraJobs.extra` | attrs | `{}` | Extra jobs merged last, highest priority |

## Custom module directories

Change which subdirectories are scanned for each module type:

```nix
purr.moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

## Extra modules from other flakes

Inject external modules alongside auto-discovered ones:

```nix
purr.extraModules = {
  nixos = [
    inputs.my-extra-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```

## Default module bundle

A `default` module that imports all discovered sub-modules is generated for
`nixosModules`, `darwinModules`, and `homeModules`. It is skipped when a discovered
module set or `extraModules` already defines `default`. Consumers can import the
bundle with:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

`bundleModules` (default `false`) controls whether `extraModules` are folded into this
bundle. Set it to `true` and leave `bundleExtraModules = true` to include them, or set
`bundleExtraModules = false` to bundle only the auto-discovered modules:

```nix
purr.bundleModules = true;        # include extraModules in the default bundle
purr.bundleExtraModules = false;  # only discovered modules in the bundle
```

## Formatter and legacy packages

Discovery works the same as in mkFlake. A `formatters/default.nix` that returns a
derivation becomes `formatter.<system>`, and `legacyPackages/<name>/default.nix`
becomes `legacyPackages.<system>.<name>`:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style

# legacyPackages/hello/default.nix
{ pkgs, ... }: pkgs.hello
```

To also scan the `by-name/` layout for legacy packages:

```nix
purr.legacyPackagesByName = true;   # also scan legacyPackages/by-name/
```

Checks, shells, apps, overlays, and templates use the same directories and module
shapes as mkFlake. See [checks and shells](/mkflake#checks-and-shells),
[apps](/mkflake#apps), and
[overlays and templates](/mkflake#overlays-and-templates).

## Outputs builder

`purr.outputsBuilder` works like mkFlake's `outputsBuilder`. It receives
`{ pkgs, system, lib, inputs, namespace }` plus every `extraArgs` key, and its result
is deep-merged with the discovered per-system outputs:

```nix
purr.outputsBuilder = { pkgs, system, lib, namespace, ... }: {
  packages.fmt = pkgs.nixfmt-rfc-style;
};
```

## Hydra CI

Generate a `hydraJobs` output that mirrors configuration outputs and adds custom jobs
from a `hydraJobs/` directory:

```nix
purr.hydraJobs = {
  enable = true;
  systems = ["x86_64-linux"];
  include = [ "nixosConfigurations" "homeConfigurations" ];
};
```

In flake-parts mode, hydraJobs mirrors the config outputs
(`nixosConfigurations`, `darwinConfigurations`, `homeConfigurations`), images,
directory jobs, and `extra`. The per-system outputs (`checks`, `packages`,
`devShells`, `legacyPackages`, `formatter`) are not auto-mirrored; add them through
`purr.hydraJobs.extra` if needed.

See the [hydraJobs](/hydrajobs) page for the full reference.

## Namespace lib output

When a `lib/` directory exists and `namespace` is set, purr exports the namespace lib
as a flake output in both mkFlake and flake-parts modes. When `namespace` is `null`,
the same lib is exported at `lib`:

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

## Extra args

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

The keys are passed to packages, shells, checks, apps, templates, system
`specialArgs`, home `extraSpecialArgs`, and `outputsBuilder`. purr's own keys
(`inputs`, `pkgs`, `namespace`, `lib`, and similar) override `extraArgs` on conflict.
