# hydraJobs

purr can generate a `hydraJobs` flake output for [Hydra CI](https://nixos.org/hydra/).
Hydra evaluates `outputs.hydraJobs` (falling back to `checks`) and builds every
derivation leaf. When enabled, purr mirrors the buildable outputs and can add custom
jobs from a `hydraJobs/` directory.

## Enabling

hydraJobs is off by default. Enable it with `hydraJobs.enable`:

```nix
# mkFlake
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hydraJobs.enable = true;
}

# flake-parts
purr = {
  enable = true;
  src = ./.;
  hydraJobs.enable = true;
};
```

## Options

### mkFlake

```nix
hydraJobs = {
  enable = true;                  # bool, default false: output hydraJobs
  as = "builds";                  # str, default "hydraJobs": output name
  dir = "hydraJobs";              # nullOr str, default null: auto-detects "hydraJobs"
  systems = ["x86_64-linux"];     # nullOr [str], default null: filter CI systems
  include = null;                 # nullOr [str], default null: auto-detect outputs
  extra = { };                    # attrs, default {}: extra jobs, highest priority
};
```

### flake-parts

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.hydraJobs.enable` | bool | `false` | Enable the hydraJobs flake output |
| `purr.hydraJobs.as` | str | `"hydraJobs"` | Name of the flake output carrying the jobs |
| `purr.hydraJobs.dir` | nullOr str | `null` | Directory for custom jobs; auto-detects `hydraJobs/` |
| `purr.hydraJobs.systems` | nullOr \[str] | `null` | Restrict CI jobs to these systems. Also filters the top-level `images` output |
| `purr.hydraJobs.include` | nullOr \[str] | `null` | Outputs to mirror; `null` auto-detects |
| `purr.hydraJobs.extra` | attrs | `{}` | Extra jobs merged last, can override anything |

## Renaming the output

By default the jobs are exposed as `outputs.hydraJobs`, which Hydra looks for. `nix
flake check` treats a `hydraJobs` output specially: it evaluates it with
import-from-derivation disabled, so a host config that uses IFD can fail the check
even when `allow-import-from-derivation` is enabled in `nix.conf`.

Set `hydraJobs.as = "builds"` to expose the jobs under a different output name that
`nix flake check` does not force. A second flake can re-export them as `hydraJobs`:

```nix
# flake.nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hydraJobs = {
    enable = true;
    as = "builds";
    systems = [ "x86_64-linux" ];
  };
}
```

```nix
# hydra/flake.nix, the flake Hydra evaluates with ?dir=hydra
{
  inputs.nix-config.url = "github:you/nix-config";
  outputs = { self, nix-config }: {
    hydraJobs = nix-config.builds;
  };
}
```

The `builds` output is lazy, so `nix flake check` on the main flake never evaluates
it. Point the Hydra jobset at `github:you/nix-config?dir=hydra`.

## What gets mirrored

When `hydraJobs.include = null` (the default), purr auto-detects the available
outputs:

| Group | Source | Job |
|-------|--------|-----|
| `checks.<system>.<name>` | `checks/` | `checks.<system>.<name>` |
| `packages.<system>.<name>` | `packages/` | `packages.<system>.<name>` |
| `devShells.<system>.<name>` | `shells/` | `devShells.<system>.<name>` |
| `legacyPackages.<system>.<name>` | `legacyPackages/` | `legacyPackages.<system>.<name>` |
| `formatter.<system>` | `formatters/` | `formatter.<system>` |
| `nixosConfigurations.<system>.<host>` | `systems/` | `config.system.build.toplevel` |
| `darwinConfigurations.<system>.<host>` | `systems/` | `system` |
| `homeConfigurations.<system>.<user@host>` | `homes/` | `activationPackage` |
| `images.<host>.<format>` | host [meta](/meta) `images` | `config.system.build.images.<format>` |

`apps` are not auto-mirrored because they are `{ type = "app"; program = ...; }`
metadata rather than derivations.

Linux hosts with `images` and no `deployable = true` are excluded from
`nixosConfigurations` and the hydraJobs config groups. Their images still appear under
`images.<host>.<format>`. See
[Image-only hosts](/systems-homes#image-only-hosts).

In flake-parts mode, the per-system rows (`checks`, `packages`, `devShells`,
`legacyPackages`, `formatter`) are not mirrored. flake-parts mode mirrors
configuration outputs, images, directory jobs, and `extra`. Add anything else through
`purr.hydraJobs.extra`.

### Manual control

Set `include` to mirror only selected outputs, or to `[]` to disable mirroring:

```nix
hydraJobs.include = [ "checks" "packages" ];          # only these two
hydraJobs.include = [ ];                              # no mirroring
hydraJobs.include = [ "checks" "nixosConfigurations" "homeConfigurations" ];
```

Valid per-system names are `checks`, `packages`, `devShells`, `apps`,
`legacyPackages`, and `formatter`. Valid config names are `nixosConfigurations`,
`darwinConfigurations`, and `homeConfigurations`.

### Architecture filter

Restrict CI jobs to specific systems:

```nix
hydraJobs.systems = [ "x86_64-linux" ];
```

## Directory jobs

Custom jobs go under `hydraJobs/<group>/<job>/default.nix`. Each job is a function
that receives `{ pkgs, system, lib, inputs, namespace, ... }` and returns a
derivation, an attrset of derivations, or `null` to skip the job for that system:

```
hydraJobs/
├── build/
│   └── hello/default.nix      → hydraJobs.build.<system>.hello
└── test/
    └── unit/default.nix       → hydraJobs.test.<system>.unit
```

```nix
# hydraJobs/build/hello/default.nix
{ pkgs, system, ... }: pkgs.hello

# hydraJobs/test/unit/default.nix
{ pkgs, system, ... }:
if system == "x86_64-linux" then
  pkgs.runCommand "unit-test" { } "echo pass > $out"
else
  null   # skip this job on other systems
```

### Extra jobs

Add jobs at the top level with `extra`. This has the highest priority and can
override anything:

```nix
hydraJobs.extra = {
  ci.gitStatus = {
    "x86_64-linux".check = pkgs.runCommand "git-check" { } "true";
  };
};
```

## Example output

With `hydraJobs.enable = true`, a mkFlake project with packages, a NixOS host, and
home configs produces:

```
hydraJobs
├── build.x86_64-linux.hello         # directory job
├── checks.x86_64-linux.good         # mirrored from checks/
├── packages.x86_64-linux.hello      # mirrored from packages/
├── homeConfigurations.x86_64-linux."alice@server"   # activationPackage
├── images.server.iso                # meta images
├── nixosConfigurations.x86_64-linux.server # toplevel
└── test.x86_64-linux.unit           # directory job
```

## The `images` output

`images` is a host meta key for Linux hosts. Declare the formats in
[host meta](/meta) and purr exposes them as `images.<host>.<format>`, whether or not
hydraJobs is enabled:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
}
```

```bash
nix build .#images.server.iso
```

A Linux host with `images` is image-only by default and is excluded from
`nixosConfigurations` and the hydraJobs config groups. Set `deployable = true` to
expose it as a configuration as well. See
[Image-only hosts](/systems-homes#image-only-hosts).

The same declarations feed `hydraJobs.images.<host>.<format>` when hydraJobs is
enabled. See [Systems & Homes](/systems-homes) for the available formats.
