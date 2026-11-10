# Host Meta

Every system host can carry metadata that purr reads during flake evaluation and
passes to the host's modules as `purr.meta`. The same data decides which images to
build and whether the host is exposed as a configuration.

## Why host meta

Host declarations used to live in the host's `default.nix`. purr had to import the
module with placeholder arguments to read them, which could fail when the module
touched `config` or `pkgs` at the top level. Host meta is a separate file or config
value that purr reads directly. The host module is not imported to decide how the
host is exposed.

## Sources and merge order

Host meta is merged from up to three sources. Later sources win:

1. Auto-generated: `name`, `host`, `arch`, `archFormat`, `format`, `isDarwin`,
   `isLinux`, `system`, and `homes`. These come from the host's directory path and
   matched homes.
2. `meta.nix`: a file next to the host's `default.nix`.
3. `hosts.<name>.meta`: flake-level config (`hosts` in `mkFlake`, `purr.hosts` in
   flake-parts).

The two user sources are deep-merged with `lib.recursiveUpdate`, so a flake-level
config can override one nested key without replacing the whole attrset.

```
auto meta -> meta.nix -> hosts.<name>.meta
 (lowest)                  (highest)
```

## `meta.nix`

Place `meta.nix` next to the host's
`systems/<arch>-<format>/<name>/default.nix`:

```
src/
└── systems/
    └── x86_64-linux/
        └── server/
            ├── default.nix
            └── meta.nix          # optional host metadata
```

### Plain attrset

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
  tier = "prod";
}
```

### Function

`meta.nix` may also be a function. purr calls it with the auto-generated meta plus
fixed values. The arguments are bound lazily, so conditions such as
`if inputs ? nix-darwin then ...` do not force nixpkgs or the module system:

```nix
# systems/x86_64-linux/server/meta.nix
{ inputs, lib, arch, ... }:
assert lib != null;
if arch == "x86_64" && inputs ? home-manager then
  {
    images = [ "iso" "qemu" ];
    tier = "prod";
  }
else
  { images = [ ]; tier = "dev"; }
```

| Parameter | Description |
|---|---|
| `inputs` | The flake inputs |
| `lib` | The merged purr lib (nixpkgs lib plus the namespace lib) |
| `namespace` | The configured namespace, or `null` |
| `extraArgs` | The configured `extraArgs` |
| `host` / `name` | Host name |
| `system` | Full triple, for example `"x86_64-linux"` |
| `arch` | Architecture, for example `"x86_64"` |
| `archFormat` | Directory name, for example `"x86_64-linux"` |
| `format` | `"linux"` or `"darwin"` |
| `isDarwin` / `isLinux` | Platform booleans |
| `homes` | Matched homes, for example `[{ user = "alice"; host = "server"; }]` |
| `...` | Extra arguments are accepted but not forced |

`pkgs`, `config`, and `options` are not provided. Meta evaluation does not evaluate a
NixOS or home-manager configuration.

## `hosts.<name>.meta`

### mkFlake

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hosts.server.meta = {
    tier = "prod";      # deep-merges over meta.nix
  };
}
```

### flake-parts

```nix
purr.hosts.server.meta = {
  tier = "prod";
};
```

Referencing a host that has no matching
`systems/<arch>-<format>/<name>/default.nix` is an error.

## Reserved keys

The auto-generated keys cannot be overridden. Setting one in `meta.nix` or
`hosts.<name>.meta` emits a warning during flake evaluation and drops the user value.

| Reserved key | Auto-generated value |
|---|---|
| `name` | Host name |
| `host` | Host name (alias of `name`) |
| `arch` | Architecture |
| `archFormat` | Arch-format directory name |
| `format` | `"linux"` or `"darwin"` |
| `isDarwin` / `isLinux` | Platform booleans |
| `system` | Full triple |
| `homes` | Matched homes |

## Behaviour keys

These keys are consumed by purr:

| Key | Type | Description |
|---|---|---|
| `images` | list of strings | Image formats to build for a Linux host. Exposed as `images.<host>.<format>`, and as `hydraJobs.images.<host>.<format>` when hydraJobs is enabled. Each format maps to `config.system.build.images.<format>` |
| `deployable` | bool | Whether the host is exposed in `nixosConfigurations` or `darwinConfigurations`. Defaults to `true` when `images` is empty or the host is darwin |
| `roles` | attrs | Maps a role name to a key of the effective inputs, for example `roles.nixpkgs = "nixpkgs-stable"`. See [roles](#roles-per-host-inputs) |

A Linux host with `images` and no explicit `deployable` is image-only. It is excluded
from the configuration outputs and the hydraJobs config groups, so its
`system.build.toplevel` is not evaluated. See
[Image-only hosts](/systems-homes#image-only-hosts).

### roles (per-host inputs)

Different hosts can build from different inputs, for example a second nixpkgs or a
different home-manager. Two pieces work together:

1. `inputsFor` filters or replaces the raw flake inputs into the effective inputs
   that purr builds from internally. See
   [mkFlake](/mkflake#per-host-inputs-multi-nixpkgs) or
   [flake-parts](/flake-parts). Default is the identity.
2. `meta.roles.<role>` points a host at an effective-input key. The role names
   (`nixpkgs`, `home-manager`, `nix-darwin`) live under `roles` so they do not collide
   with custom meta keys. If a role is absent, purr falls back to the conventional
   input key (`nixpkgs`, `home-manager` or `homeManager`, `nix-darwin` or `darwin`).

```nix
# systems/x86_64-linux/server/meta.nix
{
  roles.nixpkgs = "nixpkgs-stable";
  roles."home-manager" = "home-manager-stable";
  tier = "prod";
}
```

Role replacement is internal. It changes which input purr uses to build pkgs, system
configs, home configs, and the merged lib base. The `inputs` argument that modules
receive is never modified. Homes inherit their linked system's nixpkgs; unmatched
homes use the effective-input default. Referencing an input that is missing from the
effective inputs throws an error.

## `purr.meta`

For system modules, the merged meta is passed through `specialArgs.purr.meta`. The
home-manager bridge receives the same host meta through `extraSpecialArgs`. It always
contains the 9 auto-generated keys plus the normalized `images` and derived
`deployable`, plus any custom keys:

```nix
# systems/x86_64-linux/server/default.nix
{ purr, ... }:
{
  networking.hostName = purr.meta.name;     # "server"
  services.foo.enable = purr.meta.tier == "prod";
  system.stateVersion = "24.11";
}
```

```nix
purr.meta =
  {
    name = "server";
    host = "server";
    arch = "x86_64";
    archFormat = "x86_64-linux";
    format = "linux";
    isDarwin = false;
    isLinux = true;
    system = "x86_64-linux";
    homes = [ { user = "alice"; host = "server"; } ];
    images = [ "iso" "qemu" ];
    deployable = true;
    tier = "prod";      # custom key
  }
```

### `purr.systemMetas`

Every discovered host's merged meta is registered in `purr.systemMetas`, a pure
metadata registry keyed by host name. The registry includes the current host and is
available to both system and home modules. Reading another host's facts does not
evaluate that host's config:

```nix
# systems/x86_64-linux/server/default.nix
{ purr, ... }:
{
  services.bar.enable = purr.systemMetas.workstation.tier == "dev";
}
```

Home modules also get `purr.systemMeta`, the merged meta of the system named by the
home's host, or `null` when no matching system exists.

### Custom keys

Any key other than the reserved and behaviour keys is passed through and exposed as
`purr.meta.<key>`. This is a free-form slot for labels, groups, feature flags, or
other data that both purr and your modules need to read.

## Validation

* `images` must be a list, otherwise evaluation throws.
* `meta.nix` must evaluate to an attrset, otherwise evaluation throws.
* `hosts.<name>.meta` referencing a nonexistent host throws.
* Reserved keys are dropped with a warning, not an error.

## Homes

Standalone home modules receive `purr.meta` with home-specific fields (`user`,
`host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system`). They do not
receive the full host meta, so `images` and `deployable` are absent. Bridged homes
receive the host's merged meta as both `purr.meta` and `purr.systemMeta`; use the
`user` module argument for the username there. In both forms `purr.systemMetas` is the
host registry, and `purr.systemMeta` is the linked system's merged meta (or `null` for
an unlinked standalone home). See
[Systems & Homes: purr metadata](/systems-homes#purr-metadata).
