# mkFlake Usage

`mkFlake` builds a flake from a project directory without flake-parts. The call returns
the complete `outputs` attrset.

## Basic usage

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

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `inputs` | attrs | required | Flake inputs. `nixpkgs` is required. `home-manager` (or `homeManager`) enables home-manager outputs, and `nix-darwin` (or `darwin`) enables darwin support |
| `inputsFor` | fn | identity | Filter or replace the flake inputs that purr uses internally. Accepts `{ inputs, ... } -> inputs'` or a plain attrset. Modules still receive the raw `inputs`. See [Per-host inputs](#per-host-inputs-multi-nixpkgs) |
| `src` | path | required | Project root directory |
| `namespace` | nullOr str | `null` | Module option namespace, also used as the lib key (`lib.<namespace>`) |
| `libDir` | nullOr str | `null` | Lib directory relative to `src`; auto-detects `lib/` |
| `flattenLib` | bool | `false` | Flatten lib subdirectories into the namespace root |
| `systems` | list | `["x86_64-linux" "aarch64-linux" "aarch64-darwin"]` | Systems to generate per-system outputs for |
| `nixpkgsConfig` | attrs | `{}` | nixpkgs config such as `allowUnfree` |
| `outputsBuilder` | fn | `(_: {})` | Per-system extra outputs. Called with `{ pkgs, system, inputs, namespace, lib, ... }` plus every `extraArgs` key. The result is deep-merged with the discovered outputs |
| `modulesDir` | str | `"modules"` | Module directory name under `src` |
| `moduleTypes` | attrs | `{ nixos = [...]; darwin = [...]; home = [...]; }` | Subdirectory mapping per output |
| `extraModules` | attrs | `{}` | Raw module injection: `{ nixos = [...]; darwin = [...]; home = [...]; }` |
| `extraArgs` | attrs | `{}` | Custom values added to the arguments of every auto-discovered module, system `specialArgs`, and home `extraSpecialArgs`. purr's own keys win on conflict |
| `hosts` | attrs | `{}` | Per-host config: `hosts.<name>.meta = { images = [...]; deployable = true; roles.nixpkgs = "..."; ... }`, deep-merged over the host's `meta.nix`. See [Host Meta](/meta) |
| `bundleModules` | bool | `false` | Include `extraModules` in the generated `default` module bundle |
| `bundleExtraModules` | bool | `true` | Include extra modules in the bundle when `bundleModules` is on |
| `checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `packagesByName` | bool | `false` | Also discover packages from `packages/by-name/<shard>/<name>/package.nix` |
| `packagesToPkgs` | bool | `true` | Register discovered packages in `pkgs` as well. See [Packages](#packages) |
| `legacyPackagesDir` | nullOr str | `null` | auto-detects `legacyPackages/` |
| `legacyPackagesByName` | bool | `false` | Also discover legacy packages from the `by-name/` layout |
| `appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `templatesRecursive` | bool | `false` | Scan `templates/` recursively |
| `formatterDir` | nullOr str | `null` | auto-detects `formatters/` then `formatter/`. The `default.nix` must return a derivation |
| `systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `homesDir` | nullOr str | `null` | auto-detects `homes/` |
| `autoInject` | bool | `true` | Inject `networking.hostName`, `home.username`, and `home.homeDirectory` with `lib.mkDefault` |
| `hydraJobs` | attrs | `{}` | Hydra CI options: `{ enable, as, dir, systems, include, extra }`. See below |

## Hydra CI

`hydraJobs` mirrors buildable outputs and adds jobs from a `hydraJobs/` directory:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hydraJobs = {
    enable = true;
    systems = ["x86_64-linux"];
    include = [ "checks" "packages" "nixosConfigurations" ];
  };
}
```

See the [hydraJobs](/hydrajobs) page for the full reference.

## Customizing systems

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systems = [ "x86_64-linux" "aarch64-linux" ];
}
```

## Custom module directories

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  moduleTypes = {
    nixos = ["nixos" "shared" "container"];
  };
}
```

## Systems and homes

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systemsDir = "systems";   # or "hosts", or null to auto-detect
  homesDir = "homes";
}
```

## Per-host inputs (multi-nixpkgs)

`inputsFor` selects which inputs purr builds from. A host then points at one of those
inputs with `meta.roles.<role>`. Modules always keep the original `inputs` argument.
The replacement only affects how purr builds pkgs, system configs, home configs, and
the merged lib. See [Host Meta: roles](/meta#roles-per-host-inputs) for the role
reference.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    purr.url = "github:nixcafe/purr";
  };

  outputs = inputs:
    inputs.purr.lib.mkFlake {
      inherit inputs;
      src = ./.;
      inputsFor = { inputs, ... }: {
        inherit (inputs) nixpkgs;
        inherit (inputs) nixpkgs-unstable;
      };
      hosts.server.meta.roles.nixpkgs = "nixpkgs-unstable";
    };
}
```

The same role can be set in `meta.nix`:

```nix
# systems/x86_64-linux/server/meta.nix
{ roles.nixpkgs = "nixpkgs-unstable"; }
```

Supported role keys are `nixpkgs`, `home-manager`, and `nix-darwin`. Homes inherit
their linked system's nixpkgs; unmatched homes use the effective-input default.

## Formatter

A per-system formatter is discovered from `formatters/` or `formatter/`. The
`default.nix` receives `{ pkgs, lib, system, namespace, inputs, ... }` and must return
a derivation:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style
```

This produces `formatter.<system>`, which `nix fmt` uses. `outputsBuilder` can override
it:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  outputsBuilder = { pkgs, ... }: {
    formatter = pkgs.alejandra;
  };
}
```

## Packages

Modules under `packages/` are exposed as `packages.<system>.<name>`. When
`packagesToPkgs = true` (the default), they are also registered in `pkgs`, so any
per-system module or host config can reference them as `pkgs.<name>`:

```nix
# packages/hello/default.nix
{ lib, ... }: { /* ... */ }
```

```nix
# checks/lint/default.nix
{ pkgs, ... }: pkgs.hello   # the discovered package
```

Each discovered package is wrapped like a `callPackage` package, so
`.override` and `.overrideAttrs` work, and packages can depend on each other:

```nix
# packages/wrapper/default.nix
# `hello` resolves from `pkgs`
{ hello, ... }: hello.override { /* ... */ }
```

Registration is a nixpkgs overlay built on the package-set fixpoint. One-way
dependencies resolve lazily. Mutually recursive packages recurse, as in any nixpkgs
overlay.

Set `packagesToPkgs = false` to keep packages out of `pkgs`. They remain available as
`packages.<system>.<name>`:

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  packagesToPkgs = false;
}
```

## Legacy packages

`legacyPackages.<system>.*` is discovered from `legacyPackages/`. These packages are
not added to `pkgs`:

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

Build one with `nix build .#legacyPackages.<system>.hello`.

## Checks and shells

`checks/<name>/default.nix` becomes `checks.<system>.<name>`, and
`shells/<name>/default.nix` becomes `devShells.<system>.<name>`:

```nix
# checks/lint/default.nix
{ pkgs, ... }: pkgs.runCommand "lint" { } "true"

# shells/dev/default.nix
{ pkgs, ... }: pkgs.mkShell { packages = [ pkgs.git ]; }
```

## Apps

`apps/<name>/default.nix` becomes `apps.<system>.<name>` and must return a flake app:

```nix
# apps/hello/default.nix
{ pkgs, ... }: {
  type = "app";
  program = "${pkgs.hello}/bin/hello";
}
```

## Overlays and templates

`overlays/<name>/default.nix` becomes `overlays.<name>`, and
`templates/<name>/default.nix` becomes `templates.<name>`:

```nix
# overlays/custom/default.nix
_final: prev: {
  hello = prev.hello.overrideAttrs (_: { doCheck = false; });
}

# templates/rust/default.nix
{
  path = ./.;
  description = "A Rust project";
}
```

## Extra args

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

The keys are passed to packages, shells, checks, apps, templates, system
`specialArgs`, home `extraSpecialArgs`, and `outputsBuilder`. purr's own keys
(`inputs`, `pkgs`, `namespace`, `lib`, and similar) override `extraArgs` on conflict.
