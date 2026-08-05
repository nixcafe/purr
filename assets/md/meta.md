# Host Meta

Every system host can carry **metadata** that purr reads at flake-evaluation time and re-exposes to the host's modules as `purr.meta`. It drives host behaviour (which images to build, whether the host is deployable) and gives your modules a cheap, structured way to read per-host facts — no placeholder-arg imports, no nixpkgs/system evaluation.

## Why meta instead of module options?

Image/host declarations used to live inside the host's `default.nix` and were read back out by importing the module with placeholder arguments. That was fragile — a module touching `config`/`pkgs` at the top level would crash the cheap read, and conditional declarations were silently ignored.

Host meta is a dedicated, tiny file/config that purr reads directly. The host module is never imported just to decide how the host is exposed.

## Sources & Merge Order

Host meta is merged from up to three sources, in increasing priority (later wins):

1. **Auto-generated** — `name`, `host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system`, `homes` (derived from the host's directory path and matched homes).
2. **`meta.nix`** — a file next to the host's `default.nix`.
3. **`hosts.<name>.meta`** — flake-level config (`mkFlake` / `purr.hosts`).

The two user sources are **deep-merged** (`lib.recursiveUpdate`), so a flake-level config can override individual nested keys of a `meta.nix` without replacing the whole attrset.

```
auto meta ──► meta.nix ──► hosts.<name>.meta
  (lowest)                    (highest)
```

## `meta.nix`

Place a `meta.nix` next to the host's `systems/<arch>-<format>/<name>/default.nix`:

```
src/
└── systems/
    └── x86_64-linux/
        └── server/
            ├── default.nix
            └── meta.nix          # ← optional host metadata
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

`meta.nix` may also be a function. It is called with the auto-generated meta plus convenient fixed values — all **lazily bound**, so cheap conditionals like `if inputs ? nix-darwin then ...` cost nothing extra:

```nix
# systems/x86_64-linux/server/meta.nix
{ inputs, lib, arch, format, extraArgs, ... }:
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
| `inputs` | All flake inputs (incl. transitive inputs in mkFlake mode) |
| `lib` | The merged purr lib (nixpkgs lib + namespace lib) |
| `namespace` | The configured namespace, or `null` |
| `extraArgs` | The configured `extraArgs` (same as system modules receive) |
| `host` / `name` | Host name |
| `system` | Full triple, e.g. `"x86_64-linux"` |
| `arch` | Architecture, e.g. `"x86_64"` |
| `archFormat` | Directory name, e.g. `"x86_64-linux"` |
| `format` | `"linux"` or `"darwin"` |
| `isDarwin` / `isLinux` | Platform booleans |
| `homes` | Auto-matched homes, e.g. `[{ user = "alice"; host = "server"; }]` |
| `...` | Extra args accepted, never forced |

`pkgs`, `config`, `options` are **not** provided — the whole point is that meta evaluation never touches nixpkgs or the module system.

## `hosts.<name>.meta` (flake config)

### mkFlake

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  hosts.server.meta = {
    tier = "prod";      # overrides / deep-merges meta.nix
  };
}
```

### flake-parts

```nix
purr.hosts.server.meta = {
  tier = "prod";
};
```

Referencing a host that has no matching `systems/<arch>-<format>/<name>/default.nix` is an error.

## Reserved Keys

The auto-generated keys **cannot be overridden**. Setting one in `meta.nix` or `hosts.<name>.meta` emits a warning (to stderr during flake evaluation) and the value is silently dropped — the auto-generated value always wins.

| Reserved key | Auto-generated value |
|---|---|
| `name` | Host name |
| `host` | Host name (alias of `name`) |
| `arch` | Architecture |
| `archFormat` | Arch-format directory name |
| `format` | `"linux"` / `"darwin"` |
| `isDarwin` / `isLinux` | Platform booleans |
| `system` | Full triple |
| `homes` | Auto-matched homes |

## Behaviour Keys

These are consumed by purr itself:

| Key | Type | Description |
|---|---|---|
| `images` | `[str]` | Image formats to build. Exposed as `images.<host>.<format>` (and `hydraJobs.images.<host>.<format>` when hydraJobs is enabled). Each format maps to `config.system.build.images.<format>`. Must be a list of strings. |
| `deployable` | `bool` | Whether the host is exposed as a `nixosConfigurations`/`darwinConfigurations` output. Defaults to `true` when `images == []` or the host is darwin. |

A host with `images` and no explicit `deployable` is **image-only**: it is excluded from `nixosConfigurations`/`darwinConfigurations` (and the hydraJobs config groups), so its `system.build.toplevel` is never evaluated. See [Image-only hosts](/systems-homes#image-only-hosts-not-deployable).

## `purr.meta`

The merged meta is injected into every system host module via `specialArgs.purr.meta` (and the home-manager bridge's `extraSpecialArgs`). It always contains the 8 auto keys plus the normalized `images` and derived `deployable`, plus any custom keys you set:

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
    tier = "prod";      # ← custom key
  }
```

### `purr.systemMetas` (global host registry)

Every discovered host's merged meta is registered in `purr.systemMetas` — a pure-metadata registry keyed by host name, including the current host. It is available to both system and home modules, so you can read any other host's facts cheaply without evaluating its config:

```nix
# systems/x86_64-linux/server/default.nix
{ purr, ... }:
{
  # read another host's meta
  services.bar.enable = purr.systemMetas.workstation.tier == "dev";
}
```

Home modules additionally get `purr.systemMeta` — the merged meta of the system named by the home's host (or `null` when no matching system exists).

### Custom keys

Any key other than the reserved/behaviour keys is carried through untouched and exposed as `purr.meta.<key>`. This is a free-form slot for your own automation — role/tier labels, machine groups, feature flags, and anything else that should be cheaply readable both by purr and by your modules.

## Validation

* `images` must be a list — anything else throws.
* `meta.nix` must evaluate to an attrset — anything else throws.
* `hosts.<name>.meta` referencing a non-existent host throws.
* Reserved keys are dropped with a warning (not an error).

## For homes

Home modules receive `purr.meta` with home-specific fields (`user`, `host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system`) — **not** the full host meta (no `images`/`deployable`). They also get `purr.systemMeta` (the linked system's merged host meta, or `null` when unlinked) and `purr.systemMetas` (the global registry). See [Systems & Homes — purr Metadata](/systems-homes#purr-metadata).
