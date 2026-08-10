# API Reference

All 42 library functions are exported from a single `rec` attrset under `inputs.purr.lib`.

## Flake Builder

### `mkFlake`

Standalone flake builder. See the [mkFlake Usage](/mkflake) page for the full parameter table.

**Signature:** `mkFlake :: { inputs, src, ... } -> attrs`

## Attribute Utilities

### `optionalAttrs`

`optionalAttrs :: cond: attrs: if cond then attrs else {}`

```nix
optionalAttrs true { foo = "bar"; }  # => { foo = "bar"; }
optionalAttrs false { foo = "bar"; } # => { }
```

## System Utilities

### `defaultSystems`

`defaultSystems :: [string]`

```nix
defaultSystems  # => ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]
```

### `eachSystem`

`eachSystem :: systems: f: { system = f system; }`

Apply a function to each system, returning a system-keyed attrset.

### `eachDefaultSystem`

`eachDefaultSystem :: f: { system = f system; }`

Same as `eachSystem defaultSystems`.

## Filesystem

### `getDefaultNixFiles`

Recursively find all `default.nix` files under a path.

## Module Discovery

### `findModules`

Discover nested module tree with `_module` keys. Recursively scans a directory for `.nix` files.

### `findModulesFlat`

Discover flat (non-recursive) modules. Returns only immediate children.

### `findModulesLib`

Discover lib-like modules (nested `default.nix` files).

### `findModulesByName`

Discover packages using the `by-name/` convention (`<dir>/by-name/<shard>/<name>/package.nix`).
Returns a flat attrset of `{ name = path; }`.

### `validateByName`

Validate a by-name packages directory. Returns a list of errors; empty list means all valid.
Checks that each package's shard prefix matches its name, and that each package has a `package.nix`.

```nix
validateByName src "packages"
# => [ ]
# or errors like:
# => [ { name = "badshard"; shard = "xx"; error = "shard mismatch: ..."; } ]
```

### `loadModules`

Recursively load all `.nix` files from a directory.

### `readDirModules`

Read directory entries into a module tree structure.

### `mergeModuleTree`

Merge multiple module trees together.

### `discoverModules`

Multi-type module discovery from a modules directory. `modulesPath -> moduleTypes -> { nixos, darwin, home }`

### `collectModules`

Flatten a nested module attrset into a flat list for `imports`.

### `discoverSystems`

Discover system configs using `<arch>-<format>/<name>` convention.

### `discoverHomes`

Discover home configs using `<arch>/<user>@<host>` convention.

## Namespace Wrapping

### `deepMapAttrs`

Map over nested attrs, treating modules as leaves (not recursing into module functions).

### `wrapModule`

Wrap a single module with namespace and/or lib injection.

### `wrapModuleSet`

Wrap a module tree (nested attrset of modules) with namespace/lib injection.

## Configuration Builders

### `buildHomeConfigs`

Build home-manager configurations from discovered homes.

### `buildSystemConfigs`

Build nixos/darwin configurations from discovered systems. Hosts whose [meta](/meta) declares `images` are image-only by default and are excluded from the returned `nixosConfigurations`/`darwinConfigurations`; set `deployable = true` in the host meta to keep them deployable. Also returns an `imageRecipes` attribute — `{ host = { system; images; cfg; }; }` — consumed by `imagesFromConfigs`. Accepts `hostsMeta` (`{ <name> = metaAttrs; }`) merged over each host's `meta.nix`.

### `buildSystemRegistry`

Build the global host metadata registry — a pure-metadata `name -> merged meta` map for every discovered host, cycle-free because it never touches config `value`s. Exposed to modules as `purr.systemMetas`. Used internally by both `buildSystemConfigs` and `buildHomeConfigs`.

### `parseArchFormat`

`parseArchFormat :: "x86_64-linux" -> { arch = "x86_64"; format = "linux"; }`

### `parseUserHost`

`parseUserHost :: "alice@server" -> { user = "alice"; host = "server"; }`

### `findMatchingHomes`

Find homes matching a host across all architectures.

### `formatOutputKey`

Map format string to flake output key (`"linux" -> "nixosConfigurations"`, `"darwin" -> "darwinConfigurations"`). Throws for unsupported formats.

### `imagesFromConfigs`

`imagesFromConfigs :: imageRecipes -> systemsOrNull -> { host = { format = derivation; }; }`

Extract image derivations from image recipes. For each recipe, resolves `cfg.config.system.build.images.<format>` lazily for the formats listed in its `images` attr. Filters recipes by system when `systems` is non-null. Used by both the top-level `images` output and `hydraJobs.images`.

## Directory Resolution

### `resolveDir`

`resolveDir :: src -> dirOption -> [candidates] -> pathOrNull`

Resolve a directory from an explicit value or auto-detect from candidate paths.

### `resolveDirs`

`resolveDirs :: src -> dirOptions -> resolvedDirs`

Resolve all standard purr directories at once. Used internally by both `mkFlake` and the flake-parts module.

## Library Construction

### `buildImportedPurrLib`

Build the project's custom lib (with fix recursion). Imports a `lib/` directory recursively and provides `inputs`, `lib`, and `namespace` to each function.

### `mergePurrLib`

`mergePurrLib :: nixpkgsLib -> importedLib -> namespace -> mergedLib`

Merge the project lib into nixpkgs lib under the namespace:

```nix
mergedLib = lib                    # base: nixpkgs lib
  // { ${namespace} = ownLib }     # flake's own namespace lib
```

### `buildMergedLib`

`buildMergedLib :: { inputs, lib, importedPurrLib, namespace } -> mergedLib`

Resolve the merged lib handed to modules. The base is the flake's real `inputs.nixpkgs.lib` when available (keeping everything on one nixpkgs), falling back to the caller-provided lib otherwise; the namespace lib is then merged on top. Home configurations re-add home-manager's `lib.hm` extension so its internals keep working. This replaces the old `purrLib` module argument — modules access the merged lib via `lib`, and bridged homes via `purr.lib`.

## Auto-Discovery

### `autoModules`

Per-system auto-discovery for checks, shells, packages, and apps. Each module is imported with `pkgs` spread into the function arguments (like `callPackage`), so `{ stdenv, fetchurl, pkgs, lib, ... }` style destructuring works directly.

### `autoFormatter`

Per-system formatter discovery. Imports `<dir>/default.nix` with the same `pkgs`-spread arguments as `autoModules` and returns a single derivation, or `null` when the directory is absent. Used to produce `formatter.<system>`:

```nix
# formatters/default.nix
{ pkgs, ... }: pkgs.nixfmt-rfc-style
```

### `overlayModules`

Discover and normalize overlays from a directory.

### `templateModules`

Discover flake templates from a directory.

## Hydra CI

### `filterSystems`

`filterSystems :: attrs -> systemsOrNull -> attrs`

Filter an attrset keyed by system to only the given systems. Returns the attrset unchanged when `systems` is `null`.

### `mirrorOutputs`

`mirrorOutputs :: perSystemOutputs -> names -> systemsOrNull -> attrs`

Mirror named per-system outputs (e.g. `checks`, `packages`) into `hydraJobs.<name>.<system>.<key>` form, optionally filtered by system.

### `hydraJobsFromDir`

`hydraJobsFromDir :: src -> dir -> systems -> systemPkgs -> lib -> namespace -> inputs -> extraArgs -> attrs`

Scan `src/<dir>/<group>/<job>/default.nix` and produce `hydraJobs.<group>.<system>.<job>`. Each job is a function `{ pkgs, system, lib, inputs, namespace, ... }` returning a derivation, derivation attrset, or `null` (skipped).

### `configOutputs`

> **Internal** — exported from `lib/hydraJobs.nix` but **not** re-exported from `inputs.purr.lib`.

`configOutputs :: systemConfigurations -> homeConfigurations -> names -> systemsOrNull -> homeSystems -> attrs`

Mirror system and home configurations into hydraJobs: `nixosConfigurations` (toplevel), `darwinConfigurations` (system), `homeConfigurations` (activationPackage), grouped by system.

### `buildHydraJobs`

`buildHydraJobs :: { src, hydraJobsDir, hydraSystems, hydraJobsInclude, hydraJobsExtra, systemPkgs, perSystemOutputs, systemConfigurations, homeConfigurations, ... } -> attrs`

Combine all hydraJobs sources — directory jobs, mirrored per-system outputs, config outputs, images, and `hydraJobsExtra` (highest priority) — into the final `hydraJobs` flake output.
