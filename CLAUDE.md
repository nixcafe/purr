# CLAUDE.md — Purr

## GitHub Flow

- All changes must go through a feature branch branched from `main`.
- Branch naming: `feat/...` / `fix/...` / `refactor/...` / `chore/...` / `docs/...`.
- PR titles and bodies must be in English.

## Operation Rules

- **Never force push.** Do not use `--force-with-lease` or `--force`.
- **Ask before pushing.** Always confirm with the user before pushing to remote.
- **Ask before merging.** Always confirm with the user before merging a PR.
- **Always squash merge.** Use `gh pr merge <n> --squash --delete-branch`.
- **Tests must pass before push/PR.** Run `nix flake check` and verify "all checks passed" before any push or PR. CI MUST be green.

## Commit Rules

- All commits must be GPG signed (`git commit -S`).
- Commit messages in English, format: `type: description`.

## Code Style

- Nix: follow nixfmt output.
- No unused bindings (deadnix).
- Statix lint warnings must be clean:
  - `{ ... }:` empty patterns → use `_:` instead.
  - Prefer `inherit (x) y;` over `y = x.y;`.
  - Multi-line `&&` / `||` chains — one condition per line.

## Architecture

### Single public API entry: `lib.nix`

All library functions live in a single `rec` attrset under `lib.nix`
(flake-parts style).  `lib/*.nix` files are implementation detail — they
are imported by `lib.nix` and re-exported from the `rec` block.  Users
always go through `inputs.purr.lib.xxx`.

```
lib.nix                  # rec attrset — the public API
lib/
  attrs.nix              # optionalAttrs
  systems.nix            # defaultSystems, eachSystem, eachDefaultSystem
  fs.nix                 # getDefaultNixFiles
  modules.nix            # module discovery (findModules, discoverModules, etc.)
  namespacedModules.nix  # namespace wrapping (deepMapAttrs, wrapModule, etc.)
  configs.nix            # system/home config builders
  mkFlake.nix            # standalone mkFlake
  resolveDir.nix         # directory resolution (shared by mkFlake + flake-module)
  purrLib.nix            # lib construction (buildImportedPurrLib, mergePurrLib)
  autoModules.nix        # per-system auto-discovery
```

### Shared helpers

The three new files below eliminate ~120 lines of duplication between
`mkFlake.nix` and `flake-module.nix`:

| File | Purpose |
|------|---------|
| `lib/resolveDir.nix` | Dir resolution (`resolveDir`, `resolveDirs`) |
| `lib/purrLib.nix` | Lib construction with fix recursion (`buildImportedPurrLib`, `mergePurrLib`) |
| `lib/autoModules.nix` | Per-system auto-discovery (`autoModules`, `overlayModules`, `templateModules`) |

### Namespace Lib Merging

`purrLib` is built at flake evaluation time from the standard `lib` (nixpkgs-lib)
plus the flake's own namespace lib. Other input libs are NOT auto-merged—modules
access them directly via `inputs.xxx.lib`.

`purrLib` is passed via `specialArgs.lib` to `nixosSystem` and as
`extraSpecialArgs.purrLib` to home-manager, providing `lib.${namespace}.xxx` to
all modules.

```nix
purrLib = lib                   # standard nixpkgs lib
  // { ${namespace} = ownLib }  # flake's own namespace lib
```

Modules use `lib.${namespace}.xxx` as before. No `_module.args.lib` overrides.

## Testing

**When adding a feature or fix, you MUST write tests.** Run `nix flake check` to verify.

Tests use `lib.debug.runTests` (from nixpkgs-lib). Each test is `{ expr; expected; }`.
Returned list of failures — empty = all pass.

### How to add a test

1. Create `tests/test-<lib-module>.nix` matching the lib file:
   ```nix
   { lib }:
   {
     groupName = {
       tests = {
         "test name" = {
           expr = <expression>;
           expected = <value>;
         };
       };
     };
   }
   ```
2. Register in `tests/default.nix`:
   ```nix
   testModule = import ./test-<lib-module>.nix { inherit lib; };
   ```
   Then add to `failures`:
   ```nix
   ++ (runGroup "<group>" testModule.<group>)
   ```
3. `git add tests/test-<lib-module>.nix && nix flake check`

### Test file convention

Each test file maps 1:1 to a `lib/` module:

| Test file | Lib module tested |
|---|---|
| `test-attrs.nix` | `lib/attrs.nix` |
| `test-systems.nix` | `lib/systems.nix` |
| `test-fs.nix` | `lib/fs.nix` |
| `test-modules.nix` | `lib/modules.nix` |
| `test-namespacedModules.nix` | `lib/namespacedModules.nix` |
| `test-configs.nix` | `lib/configs.nix` |
| `test-mkFlake.nix` | `lib/mkFlake.nix` |
| `test-resolveDir.nix` | `lib/resolveDir.nix` |
| `test-purrLib.nix` | `lib/purrLib.nix` |
| `test-autoModules.nix` | `lib/autoModules.nix` |

### Integration testing with the demo

The `tests/demo/` directory is a standalone flake that exercises all
purr features end-to-end (modules, lib, packages, shells, checks,
overlays, templates, apps, systems, homes, namespace bridge).

```bash
cd tests/demo && nix flake check
```

### Fixtures

`tests/fixtures/` provides minimal directory trees for module-discovery
unit tests.  System/home fixture files return `{ }`.  Lib fixture files
return a function (`_: { someKey = ...; }`) because they are imported
with arguments via `buildImportedPurrLib`.  Keep fixtures minimal —
they are Git-tracked for reproducibility.

For module-arg tests, use `lib.evalModules` with `specialArgs = { pkgs = { ... }; }`
to simulate module evaluation. For mkFlake integration tests, mock `nixosSystem`
/ `homeManagerConfiguration` to avoid full nixpkgs evaluation — see
`tests/test-mkFlake.nix` for examples.
