# hydraJobs

purr can generate a `hydraJobs` flake output for [Hydra CI](https://nixos.org/hydra/). Hydra evaluates `outputs.hydraJobs` (falling back to `checks`) and every derivation leaf becomes a build job. purr makes this automatic — everything buildable in your flake is mirrored into `hydraJobs` with zero configuration, plus you can add custom jobs from a directory and fine-tune which outputs are included.

## Enabling

hydraJobs is **off by default**. Turn it on with the `hydraJobs.enable` option:

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
  enable = true;                  # bool, default false — output hydraJobs
  dir = "hydraJobs";              # nullOr str, default null — auto-detects "hydraJobs"
  systems = ["x86_64-linux"];     # nullOr [str], default null — filter CI systems
  include = null;                 # nullOr [str], default null — auto-detect all outputs
  extra = { };                    # attrs, default {} — extra jobs, highest priority
};
```

### flake-parts

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.hydraJobs.enable` | bool | `false` | Enable the `hydraJobs` flake output |
| `purr.hydraJobs.dir` | nullOr str | `null` | Directory for custom jobs, auto-detects `hydraJobs/` |
| `purr.hydraJobs.systems` | nullOr \[str] | `null` | Filter which systems get CI jobs |
| `purr.hydraJobs.include` | nullOr \[str] | `null` | Which outputs to mirror (see below) |
| `purr.hydraJobs.extra` | attrs | `{}` | Extra jobs merged last, can override anything |

## What Gets Mirrored

When `hydraJobs.include = null` (default), purr auto-discovers **everything buildable**:

| Group | Source | Job |
|-------|--------|-----|
| `checks.<system>.<name>` | `checks/` | `checks.<system>.<name>` |
| `packages.<system>.<name>` | `packages/` | `packages.<system>.<name>` |
| `devShells.<system>.<name>` | `shells/` | `devShells.<system>.<name>` |
| `legacyPackages.<system>.<name>` | `legacyPackages/` | `legacyPackages.<system>.<name>` |
| `formatter.<system>` | `formatters/` | `formatter.<system>` |
| `nixosConfigs.<system>.<host>` | `systems/` | `config.system.build.toplevel` |
| `darwinConfigs.<system>.<host>` | `systems/` | system derivation |
| `homeConfigs.<system>.<user@host>` | `homes/` | `activationPackage` |
| `images.<host>.<format>` | `purr.images` option | `config.system.build.images.<format>` |

> **Note:** `apps` are **not** mirrored, even when present, because apps are `{ type = "app"; program = ...; }` metadata rather than derivations — Hydra cannot build them.

> **Note:** image-only hosts (hosts with `purr.images` set and no `purr.deployable = true`) are excluded from `nixosConfigs`/`darwinConfigs` and never get a `toplevel` job. Their images still show up under `images.<host>.<format>`. See [Image-only hosts](/systems-homes#image-only-hosts-not-deployable).

> **Note (flake-parts only):** the *per-system* rows in the table above (`checks`, `packages`, `devShells`, `legacyPackages`, `formatter`) are only mirrored in **mkFlake** mode. In **flake-parts** mode, hydraJobs mirrors the config outputs (`nixosConfigs`, `darwinConfigs`, `homeConfigs`), images, directory jobs, and `extra` — but not the per-system outputs. Specify them with `include` in mkFlake mode; in flake-parts mode use `hydraJobs.extra` for anything beyond the config outputs.

### Manual control

Set `include` to an explicit list to mirror only what you want, or `[]` to disable mirroring entirely:

```nix
hydraJobs.include = [ "checks" "packages" ];          # only these two
hydraJobs.include = [ ];                              # no mirroring at all
hydraJobs.include = [ "checks" "nixosConfigs" "homeConfigs" ];
```

Valid per-system names: `checks`, `packages`, `devShells`, `apps`, `legacyPackages`, `formatter`.
Valid config names: `nixosConfigs`, `darwinConfigs`, `homeConfigs`.

### Architecture filter

Restrict CI jobs to specific systems (Hydra has no built-in system filtering — you control this in the flake):

```nix
hydraJobs.systems = [ "x86_64-linux" ];
```

## Directory Jobs

Custom CI jobs go under `hydraJobs/<group>/<job>/default.nix`. Each job is a function receiving `{ pkgs, system, lib, inputs, namespace, ... }` that returns a derivation, an attrset of derivations, or `null` (skip for that system):

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

Add arbitrary jobs at the top level with `extra` — this has the highest priority and can override anything:

```nix
hydraJobs.extra = {
  ci.gitStatus = {
    x86_64-linux.check = pkgs.runCommand "git-check" { } "true";
  };
};
```

## Example Output

With `hydraJobs.enable = true`, a project with packages, a NixOS host, and home configs produces:

```
hydraJobs
├── build.x86_64-linux.hello         # directory job
├── checks.x86_64-linux.good         # mirrored from checks/
├── packages.x86_64-linux.hello      # mirrored from packages/
├── homeConfigs.x86_64-linux.alice@server   # activationPackage
├── images.server.iso                # purr.images
├── nixosConfigs.x86_64-linux.server # toplevel
└── test.x86_64-linux.unit           # directory job
```

## Related: the `images` Output

`purr.images` is a **system option** — declare which image formats to build for a host. When set, purr exposes them as a top-level `images.<host>.<format>` output **regardless of whether hydraJobs is enabled**, so you can build an ISO directly:

```nix
# systems/x86_64-linux/server/default.nix
{
  purr.images = [ "iso" "qemu" ];
}
```

```bash
nix build .#images.server.iso
```

A host with `purr.images` is image-only by default: it is excluded from `nixosConfigurations` and from the `nixosConfigs`/`darwinConfigs` hydraJobs groups. Set `purr.deployable = true` to also expose it as a deployable configuration. See [Image-only hosts](/systems-homes#image-only-hosts-not-deployable).

The same declarations also feed `hydraJobs.images.<host>.<format>` when hydraJobs is enabled. See [Systems & Homes](/systems-homes) for available formats.
