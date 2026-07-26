# API Reference

All library functions are exported from a single `rec` attrset under `inputs.purr.lib`.

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

Build nixos/darwin configurations from discovered systems.

### `parseArchFormat`

`parseArchFormat :: "x86_64-linux" -> { arch = "x86_64"; format = "linux"; }`

### `parseUserHost`

`parseUserHost :: "alice@server" -> { user = "alice"; host = "server"; }`

### `findMatchingHomes`

Find homes matching a host across all architectures.

### `formatOutputKey`

Map format string to flake output key (`"linux" -> "nixosConfigurations"`, `"darwin" -> "darwinConfigurations"`). Throws for unsupported formats.

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
purrLib = lib                   # standard nixpkgs lib
  // { ${namespace} = ownLib }  # flake's own namespace lib
```

## Auto-Discovery

### `autoModules`

Per-system auto-discovery for checks, shells, packages, and apps. Each module is imported with `pkgs` spread into the function arguments (like `callPackage`), so `{ stdenv, fetchurl, pkgs, lib, ... }` style destructuring works directly.

### `overlayModules`

Discover and normalize overlays from a directory.

### `templateModules`

Discover flake templates from a directory.
