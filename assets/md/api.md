# API Reference

The library exports 43 functions from a single `rec` attrset under
`inputs.purr.lib`.

## Flake builder

### `mkFlake`

Build a flake from a project directory. See the [mkFlake Usage](/mkflake) page for the
parameter table.

**Signature:** `mkFlake :: { inputs, src, ... } -> attrs`

## Attribute utilities

### `optionalAttrs`

`optionalAttrs :: cond: attrs: if cond then attrs else {}`

```nix
optionalAttrs true { foo = "bar"; }  # => { foo = "bar"; }
optionalAttrs false { foo = "bar"; } # => { }
```

## System utilities

### `defaultSystems`

`defaultSystems :: [string]`

```nix
defaultSystems  # => ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
```

### `eachSystem`

`eachSystem :: [string] -> (string -> attrs) -> attrs`

Apply a function to each system and return a system-keyed attrset.

### `eachDefaultSystem`

`eachDefaultSystem :: (string -> attrs) -> attrs`

Same as `eachSystem defaultSystems`.

## Filesystem

### `getDefaultNixFiles`

Recursively find directories containing a `default.nix`. Returns a list of
`{ path, relPath }` records, where `path` is the file and `relPath` is its directory.

## Module discovery

### `findModules`

Build a nested module tree from the `default.nix` files under
`<parentDir>/<type>`. Each directory with a `default.nix` gets a `_module` entry.

**Signature:** `findModules :: parentDir -> type -> attrs`

### `findModulesFlat`

Discover only the immediate subdirectories of `<parentDir>/<type>` that contain a
`default.nix`.

**Signature:** `findModulesFlat :: parentDir -> type -> attrs`

### `findModulesLib`

Discover lib-like modules: every `default.nix` under `<parentDir>/<type>` becomes a
nested attrset entry. The root `default.nix` is handled by
`buildImportedPurrLib`, not by this function.

**Signature:** `findModulesLib :: parentDir -> type -> attrs`

### `findModulesByName`

Discover packages using the `by-name/` layout
(`<dir>/by-name/<shard>/<name>/package.nix`). Returns a flat attrset of
`{ name = path; }`.

### `validateByName`

Validate a by-name packages directory. Returns a list of errors; an empty list means
all entries are valid. Each package's shard prefix must match its name, and each
package must have a `package.nix`.

```nix
validateByName src "packages"
# => [ ]
# or errors such as:
# => [ { name = "badshard"; shard = "xx"; error = "shard mismatch: ..."; } ]
```

### `loadModules`

Recursively load all `.nix` files from a directory.

### `readDirModules`

Read a directory into a module tree, using `_module` for a `default.nix` and
recursing into subdirectories.

### `mergeModuleTree`

Merge two module trees. When both sides define `_module`, their imports are combined.

### `discoverModules`

Multi-type module discovery. Takes a modules directory and the `moduleTypes` mapping
and returns `{ nixos, darwin, home }`.

**Signature:** `discoverModules :: modulesPath -> moduleTypes -> attrs`

### `collectModules`

Flatten a nested module attrset into a flat list for `imports`.

### `discoverSystems`

Discover system configs using the `<arch>-<format>/<name>/default.nix` layout.

### `discoverHomes`

Discover home configs using the `<arch>-<format>/<user>@<host>/default.nix` layout.

## Namespace wrapping

### `deepMapAttrs`

Map over nested attrsets, treating modules as leaves instead of recursing into them.

### `wrapModule`

Wrap one module with namespace and lib injection.

### `wrapModuleSet`

Wrap a module tree (a nested attrset of modules) with namespace and lib injection.

## Configuration builders

### `buildHomeConfigs`

Build home-manager configurations from discovered homes.

**Signature:** `buildHomeConfigs :: { discoveredHomes, discoveredSystems, inputs, ... } -> attrs`

### `buildSystemConfigs`

Build NixOS and darwin configurations from discovered systems. Linux hosts whose
[meta](/meta) declares `images` are image-only by default and are excluded from the
returned `nixosConfigurations` and `darwinConfigurations`. Set `deployable = true` in
the host meta to keep them deployable.

The result also contains:

* `configSystems`: host to system-string mapping, used by hydraJobs grouping
* `imageRecipes`: `{ host = { system; images; cfg; }; }`, consumed by
  `imagesFromConfigs`

Accepts `hostsMeta` (`{ <name> = metaAttrs; }`) merged over each host's `meta.nix`.

### `buildSystemRegistry`

Build the host metadata registry. Returns `{ hostMeta, registry }`, where `registry`
is a `name -> merged meta` map for every discovered host. The registry never touches
config values and is exposed to modules as `purr.systemMetas`. It is used by both
`buildSystemConfigs` and `buildHomeConfigs`.

### `formatOutputKey`

Map a format string to its flake output key:
`"linux" -> "nixosConfigurations"`, `"darwin" -> "darwinConfigurations"`. Throws for
other formats.

### `parseArchFormat`

`parseArchFormat :: "x86_64-linux" -> { arch = "x86_64"; format = "linux"; }`

Returns `{ arch = null; format = null; }` when the string does not match.

### `parseUserHost`

`parseUserHost :: "alice@server" -> { user = "alice"; host = "server"; }`

Returns `{ user = null; host = null; }` when the string does not match.

### `findMatchingHomes`

Find homes matching a host across all architectures. Returns a list of
`{ user, path }`.

### `imagesFromConfigs`

`imagesFromConfigs :: imageRecipes -> systemsOrNull -> { host = { format = derivation; }; }`

Extract image derivations from image recipes. For each recipe, it resolves
`cfg.config.system.build.images.<format>` lazily for the formats listed in
`recipe.images`. When `systems` is non-null, recipes are filtered by system. Used by
both the top-level `images` output and `hydraJobs.images`.

## Directory resolution

### `resolveDir`

`resolveDir :: src -> dirOption -> [candidates] -> pathOrNull`

Use the explicit option value when it is not `null`; otherwise return the first
candidate that exists under `src`.

### `resolveDirs`

`resolveDirs :: src -> dirOptions -> resolvedDirs`

Resolve every standard purr directory at once. Used by both `mkFlake` and the
flake-parts module. The result includes `hydraJobsDir`.

## Library construction

### `buildImportedPurrLib`

Build the project's custom lib. Imports the `lib/` directory and provides `inputs`,
`lib`, and `namespace` to each function module.

### `mergePurrLib`

`mergePurrLib :: nixpkgsLib -> importedLib -> namespace -> mergedLib`

Merge the project lib into nixpkgs lib under the namespace:

```nix
mergedLib = lib                    # base: nixpkgs lib
  // { ${namespace} = ownLib }     # project namespace lib
```

When `namespace` is `null`, the project lib is merged at the top level.

### `buildMergedLib`

`buildMergedLib :: { effectiveInputs, lib, importedPurrLib, namespace } -> mergedLib`

Resolve the merged lib handed to modules. The base is
`effectiveInputs.nixpkgs.lib` when available, otherwise the caller-provided `lib`.
The namespace lib is merged on top. Home configurations re-add home-manager's
`lib.hm` extension so home-manager internals keep working.

## Auto-discovery

### `autoModules`

Per-system auto-discovery for directories such as checks, shells, packages, legacy
packages, and apps. Each module is imported with the whole `pkgs` attrset spread into
its arguments, like `callPackage`, so destructuring works directly:
`{ stdenv, fetchurl, pkgs, lib, ... }`.

### `autoPackages`

Per-system package discovery for `packages/`. It works like `autoModules`, but each
discovered package is wrapped with `purrLib.makeOverridable`, so `.override` and
`.overrideAttrs` work like a `callPackage` package. Used for the
`packages.<system>.*` output and for the overlay that registers packages in `pkgs`
(`packagesToPkgs`).

### `autoFormatter`

Per-system formatter discovery. Imports `<dir>/default.nix` with the same
`pkgs`-spread arguments as `autoModules` and returns a single derivation, or `null`
when the directory is absent. Used to produce `formatter.<system>`:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style
```

### `overlayModules`

Discover and normalize overlays from a directory. Plain `final: prev: attrs` overlays
are passed through; overlays that return another overlay are normalized.

### `templateModules`

Discover flake templates from a directory.

## Hydra CI

### `filterSystems`

`filterSystems :: attrs -> systemsOrNull -> attrs`

Filter an attrset keyed by system to the given systems. Returns the attrset unchanged
when `systems` is `null`.

### `mirrorOutputs`

`mirrorOutputs :: perSystemOutputs -> names -> systemsOrNull -> attrs`

Mirror named per-system outputs into `hydraJobs.<name>.<system>.<key>` form,
optionally filtered by system.

### `hydraJobsFromDir`

`hydraJobsFromDir :: src -> dir -> systems -> systemPkgs -> lib -> namespace -> inputs -> extraArgs -> attrs`

Scan `src/<dir>/<group>/<job>/default.nix` and produce
`hydraJobs.<group>.<system>.<job>`. Each job is a function
`{ pkgs, system, lib, inputs, namespace, ... }` that returns a derivation, a
derivation attrset, or `null` to skip the job.

### `configOutputs`

Internal: exported from `lib/hydraJobs.nix` but not re-exported from
`inputs.purr.lib`.

`configOutputs :: systemConfigs -> homeConfigs -> names -> systemsOrNull -> homeSystems -> attrs`

Mirror system and home configurations into hydraJobs:
`nixosConfigurations` (toplevel), `darwinConfigurations` (system), and
`homeConfigurations` (activationPackage), grouped by system.

### `buildHydraJobs`

`buildHydraJobs :: { src, hydraJobsDir, hydraSystems, hydraJobsInclude, hydraJobsExtra, systemPkgs, perSystemOutputs, systemConfigs, homeConfigs, homeSystems, lib, namespace, inputs, extraArgs } -> attrs`

Combine the hydraJobs sources: directory jobs, mirrored per-system outputs, config
outputs, images, and `hydraJobsExtra` (highest priority).
