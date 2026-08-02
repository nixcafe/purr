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

## Host Metadata (meta)

Hosts can carry metadata that purr reads at flake-evaluation time (cheap, no
nixpkgs/system eval) and re-exposes to the host's modules via `purr.meta`.

### Sources (merged in increasing priority)

1. **Auto-generated** — `name`, `arch`, `archFormat`, `format`, `isDarwin`,
   `isLinux`, `system`, `homes` (derived from the host's directory path and
   matched homes).
2. **`meta.nix`** next to the host's `systems/<arch>-<format>/<name>/default.nix`.
   A plain attrset or a function called with
   `{ inputs, lib, namespace, extraArgs, host, name, system, arch, archFormat,
   format, isDarwin, isLinux, homes, ... }` (all lazily bound, so cheap
   conditionals like `if inputs ? nix-darwin then ...` are free).
3. **Flake config** — `hosts.<name>.meta` in `mkFlake` /
   `purr.hosts.<name>.meta` in flake-parts. Deep-merged (leaf wins) on top of
   `meta.nix`.

### Reserved keys

The auto-generated keys listed above **cannot be overridden**. Setting one in
any user meta source emits a warning and the value is silently dropped, so the
auto structure is guaranteed to win. Referencing an unknown host via
`hosts.<name>.meta` is an error.

### Behaviour keys purr consumes

- `images` — list of image formats, driving the `flake.images` / hydraJobs
  `images` output (`config.system.build.images.<format>`).
- `deployable` — whether the host is exposed as a
  `nixosConfigurations`/`darwinConfigurations` output. Defaults to `true` when
  `images == []` or the host is darwin; a host with `images` is image-only by
  default (excluded from config outputs and config hydraJobs groups).

Everything else in the merged meta is a free-form custom key exposed as
`purr.meta.<key>` for user automation.

### `purr.meta` injection

The merged meta (always containing the 8 auto keys + normalized `images` +
derived `deployable`) is threaded to host modules as `purr.meta` in
`nixosSystem`/`darwinSystem` `specialArgs` and the home-manager bridge
`extraSpecialArgs`. Standalone `homeConfigurations` do not receive `purr.meta`.

## Testing

**When adding a feature or fix, you MUST write tests.** Run `nix flake check` to verify.

Tests live under `tests/` and use a custom runner (`tests/runner.nix`) — NOT
`lib.debug.runTests` (which silently skips any group whose name does not start
with "test", which is how the old suite always reported green). The runner
executes every registered test and reports exceptions as failures.

### Test file structure

Each test module returns an attrset of groups:

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

A test passes when `expr == expected` (deep structural equality). A throwing
`expr` is reported as a failure, not a crash.

### Test layout

```
tests/
├── default.nix              # entry: { lib } -> list of failures (empty = pass)
├── runner.nix               # custom runner (runTest / runGroup / runTestModule)
├── list-tests.nix           # auto-discover every test-*.nix under unit/ + integration/
├── report.nix               # one pure eval -> full PASS/FAIL report (used by the check)
├── run-tests.sh             # run in the shell: live per-test output
├── unit/                    # 1:1 unit tests for each lib/ module (auto-discovered)
│   ├── test-attrs.nix
│   ├── test-systems.nix
│   ├── test-fs.nix
│   ├── test-modules.nix
│   ├── test-namespacedModules.nix
│   ├── test-resolveDir.nix
│   ├── test-purrLib.nix
│   ├── test-autoModules.nix
│   ├── test-configs.nix
│   ├── test-hydraJobs.nix
│   └── test-mkFlake.nix
├── integration/             # real-project integration tests (auto-discovered)
│   ├── harness.nix          # shared real-eval mocks (nixosSystem/darwin/home-manager)
│   ├── mocks/nixpkgs/       # importable mock nixpkgs for per-system pkgs
│   ├── project/             # full-featured purr project exercising every feature
│   ├── test-mkFlake.nix     # mkFlake pipeline + mutual dependencies + special cases
│   └── test-flakeParts.nix  # flake-parts module integration
└── fixtures/                # minimal dir trees for discovery unit tests
```

### Adding a test

Drop a new file `tests/unit/test-<name>.nix` (or `tests/integration/test-<name>.nix`)
and it is **auto-discovered** by `list-tests.nix` — the shell runner, the Nix
report, and the `purr-tests` check all pick it up. No registration needed.

### Running the tests

```bash
# Via Nix — the check derivation writes the full report into its result:
nix build .#checks.x86_64-linux.purr-tests && cat result   # all green -> report
nix log .#checks.x86_64-linux.purr-tests                    # failures -> report in log
nix flake check                                            # CI gate (pre-commit + purr-tests)

# Via the dev shell — a live per-test runner:
nix develop --command purr-test
# or directly (no dev shell):
tests/run-tests.sh

# Fast iteration on one file:
nix eval --json --impure --expr 'let
  lib = (builtins.getFlake "github:nix-community/nixpkgs.lib").lib;
  runner = import ./tests/runner.nix { inherit lib; };
  t = import ./tests/unit/test-configs.nix { inherit lib; };
in builtins.map (f: f.group + "." + f.testName) (runner.runTestModule t)'
```

`report.nix` computes the full report in a single pure evaluation, so the check
derivation is fast. `run-tests.sh` instead evaluates each test individually
(Nix is lazy, so a single eval cannot stream results) for live per-test
progress.

### Integration tests evaluate the real module system

The integration tests run `mkFlake` on `tests/integration/project` and verify
every output. `nixosSystem` / `darwinSystem` / `homeManagerConfiguration` are
mocked to evaluate their module lists through the real `lib.evalModules` (with
minimal shim options declared in `harness.nix`), so generated system/home
configs are genuinely evaluated — auto-injection, the namespace bridge
(`purr.users.<name>.homeConfig`), linked homes, image-only hosts, by-name
packages, hydraJobs mirroring, and more are all asserted against real
evaluation, not string inspection.

### Gotchas (learned the hard way)

- Never pass a path to a nonexistent directory into a function that calls
  `builtins.readDir` — Nix's path-existence error is not caught by
  `builtins.tryEval` and crashes the run.
- Never deep-compare `lib` or large attrsets with `==` (forces huge lazy
  values). Compare markers / keys instead.
- Never compare functions with `==` — coerce with `builtins.isFunction`,
  `builtins.attrNames`, or `toString` first.
- `imagesFromConfigs` takes the `imageRecipes` shape
  (`{ host = { system; images; cfg = { config = { system.build.images }; }; }; }`),
  not the `nixosConfigurations` shape.
- Host metadata is read from `meta.nix` / `hosts.<name>.meta`, never from the
  host module — host modules must not (and need not) declare `purr.images` /
  `purr.deployable`.
