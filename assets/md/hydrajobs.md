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
  as = "builds";                  # str, default "hydraJobs" — output name (see below)
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
| `purr.hydraJobs.as` | str | `"hydraJobs"` | Name of the flake output carrying the jobs |
| `purr.hydraJobs.dir` | nullOr str | `null` | Directory for custom jobs, auto-detects `hydraJobs/` |
| `purr.hydraJobs.systems` | nullOr \[str] | `null` | Filter which systems get CI jobs |
| `purr.hydraJobs.include` | nullOr \[str] | `null` | Which outputs to mirror (see below) |
| `purr.hydraJobs.extra` | attrs | `{}` | Extra jobs merged last, can override anything |

## Renaming the output (`as`)

By default the jobs are exposed as `outputs.hydraJobs`, which is what Hydra looks
for. `nix flake check` treats a `hydraJobs` output specially: it evaluates it
**with import-from-derivation disabled**, so any host config that uses IFD (e.g.
a palette/background rendered from a derivation) fails the check even if
`allow-import-from-derivation` is enabled in your nix.conf.

Set `hydraJobs.as = "builds"` to expose the same jobs under a different output
name that `nix flake check` does not force-evaluate. Then a tiny second flake
re-exports them as `hydraJobs` for Hydra:

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
# hydra/flake.nix — the flake Hydra evaluates (via ?dir=hydra)
{
  inputs.nix-config.url = "github:you/nix-config";
  outputs = { self, nix-config }: {
    hydraJobs = nix-config.builds;
  };
}
```

The `builds` output is fully lazy, so `nix flake check` on the main flake never
evaluates it. Point the Hydra jobset at the re-exporting flake
(`github:you/nix-config?dir=hydra`) and everything else stays identical.

## What Gets Mirrored

When `hydraJobs.include = null` (default), purr auto-discovers **everything buildable**:

| Group | Source | Job |
|-------|--------|-----|
| `checks.<system>.<name>` | `checks/` | `checks.<system>.<name>` |
| `packages.<system>.<name>` | `packages/` | `packages.<system>.<name>` |
| `devShells.<system>.<name>` | `shells/` | `devShells.<system>.<name>` |
| `legacyPackages.<system>.<name>` | `legacyPackages/` | `legacyPackages.<system>.<name>` |
| `formatter.<system>` | `formatters/` | `formatter.<system>` |
| `nixosConfigurations.<system>.<host>` | `systems/` | `config.system.build.toplevel` |
| `darwinConfigurations.<system>.<host>` | `systems/` | system derivation |
| `homeConfigurations.<system>.<user@host>` | `homes/` | `activationPackage` |
| `images.<host>.<format>` | host [meta](/meta) `images` | `config.system.build.images.<format>` |

> **Note:** `apps` are **not** mirrored, even when present, because apps are `{ type = "app"; program = ...; }` metadata rather than derivations — Hydra cannot build them.

> **Note:** image-only hosts (hosts with `images` set in their [meta](/meta) and no `deployable = true`) are excluded from `nixosConfigurations`/`darwinConfigurations` and never get a `toplevel` job. Their images still show up under `images.<host>.<format>`. See [Image-only hosts](/systems-homes#image-only-hosts-not-deployable).

> **Note (flake-parts only):** the *per-system* rows in the table above (`checks`, `packages`, `devShells`, `legacyPackages`, `formatter`) are only mirrored in **mkFlake** mode. In **flake-parts** mode, hydraJobs mirrors the config outputs (`nixosConfigurations`, `darwinConfigurations`, `homeConfigurations`), images, directory jobs, and `extra` — but not the per-system outputs. Specify them with `include` in mkFlake mode; in flake-parts mode use `hydraJobs.extra` for anything beyond the config outputs.

### Manual control

Set `include` to an explicit list to mirror only what you want, or `[]` to disable mirroring entirely:

```nix
hydraJobs.include = [ "checks" "packages" ];          # only these two
hydraJobs.include = [ ];                              # no mirroring at all
hydraJobs.include = [ "checks" "nixosConfigurations" "homeConfigurations" ];
```

Valid per-system names: `checks`, `packages`, `devShells`, `apps`, `legacyPackages`, `formatter`.
Valid config names: `nixosConfigurations`, `darwinConfigurations`, `homeConfigurations`.

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
├── homeConfigurations.x86_64-linux.alice@server   # activationPackage
├── images.server.iso                # meta images
├── nixosConfigurations.x86_64-linux.server # toplevel
└── test.x86_64-linux.unit           # directory job
```

## Related: the `images` Output

`images` is a **host meta key** — declare which image formats to build for a host in its [host meta](/meta). When set, purr exposes them as a top-level `images.<host>.<format>` output **regardless of whether hydraJobs is enabled**, so you can build an ISO directly:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
}
```

```bash
nix build .#images.server.iso
```

A host with `images` is image-only by default: it is excluded from `nixosConfigurations` and from the `nixosConfigurations`/`darwinConfigurations` hydraJobs groups. Set `deployable = true` in the host meta to also expose it as a deployable configuration. See [Image-only hosts](/systems-homes#image-only-hosts-not-deployable).

The same declarations also feed `hydraJobs.images.<host>.<format>` when hydraJobs is enabled. See [Systems & Homes](/systems-homes) for available formats.
