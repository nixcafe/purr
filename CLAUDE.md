# CLAUDE.md

Working notes for purr.

## Git workflow

- Make changes on a feature branch off `main`.
- Branch names: `feat/...`, `fix/...`, `refactor/...`, `chore/...`, `docs/...`.
- PR titles and bodies are in English.

## Rules

- Don't force push.
- Ask before pushing to the remote.
- Ask before merging a PR.
- Squash merge only: `gh pr merge <n> --squash --delete-branch`.
- Run `nix flake check` before pushing or opening a PR. CI must be green.

## Commits

- Sign commits with `git commit -S`.
- Use English commit messages in the form `type: description`.

## Style

- Run nixfmt.
- No unused bindings (deadnix).
- Keep statix quiet:
  - Replace `{ ... }:` with `_:`.
  - Prefer `inherit (x) y;` over `y = x.y;`.
  - In multi-line `&&` / `||` chains, one condition per line.

## Architecture

### Public API: `lib.nix`

All library functions live in one `rec` attrset in `lib.nix`, in the flake-parts style.
Files under `lib/` are implementation details. `lib.nix` imports them and re-exports
them from the `rec` block. Users go through `inputs.purr.lib.xxx`.

```
lib.nix                  # rec attrset: the public API
lib/
  attrs.nix              # optionalAttrs
  args.nix               # purrArgs: shared module-arg merge (extraArgs + purr keys)
  systems.nix            # defaultSystems, eachSystem, eachDefaultSystem
  fs.nix                 # getDefaultNixFiles
  modules.nix            # module discovery (findModules, discoverModules, etc.)
  namespacedModules.nix  # namespace wrapping (deepMapAttrs, wrapModule, etc.)
  configs.nix            # system/home config builders
  mkFlake.nix            # standalone mkFlake
  resolveDir.nix         # directory resolution (shared by mkFlake + flake-module)
  resolveInput.nix       # effective-input role resolution (resolveRole, defaults)
  purrLib.nix            # lib construction (buildImportedPurrLib, mergePurrLib)
  autoModules.nix        # per-system auto-discovery (autoModules, autoPackages, ...)
```

### Shared helpers

These three files remove about 120 lines of duplication between `mkFlake.nix` and
`flake-module.nix`:

| File | Purpose |
|------|---------|
| `lib/resolveDir.nix` | Dir resolution (`resolveDir`, `resolveDirs`) |
| `lib/purrLib.nix` | Lib construction (`buildImportedPurrLib`, `mergePurrLib`, `buildMergedLib`) |
| `lib/autoModules.nix` | Per-system auto-discovery (`autoModules`, `autoPackages`, `overlayModules`, `templateModules`) |

### Package auto-registration (`packagesToPkgs`)

Modules under `packages/` are exposed as `packages.<system>.*` and, when
`packagesToPkgs` is on (the default), added to `pkgs`. That makes them available as
`pkgs.<name>`, and other discovered modules can take them as arguments: `importMod` and
`importPackagesMod` pass the whole `pkgs` attrset to every module, so
`{ pkgs, hello, ... }` works.

- `lib/autoModules.nix`: `autoPackages` is `autoModules` with each package wrapped in
  `makeOverridable`, so `.override` and `.overrideAttrs` work like a `callPackage`
  package.
- `lib/mkFlake.nix` and `flake-module.nix`: build
  `packagesOverlay = final: _: autoPackages … final …`, append it to
  `sharedOverlays` when `packagesToPkgs` is on,
  and use `autoPackages` for the `packages` output. `sharedOverlays` also goes to the
  NixOS/darwin/home builders, so host `pkgs` see the same packages.

`packagesOverlay` only uses the `final` fixpoint, never the outer `pkgs` binding.
`autoPackages` evaluates packages lazily, so one-way dependencies resolve without
recursion. Mutually recursive packages recurse, as in any nixpkgs overlay. Keep new code
on `final` and `makeOverridable`; don't reach for the eager `pkgs`.

### Merging the namespace lib

The merged lib is built at flake evaluation time by `buildMergedLib`. Its base is the
flake's real `inputs.nixpkgs.lib` when available (otherwise purr's nixpkgs-lib or the
host module-system lib), plus the flake's namespace lib. Libs from other inputs are not
merged automatically; modules use them through `inputs.xxx.lib`.

```nix
mergedLib = inputs.nixpkgs.lib            # base: the user's real nixpkgs
  // { ${namespace} = ownLib }            # flake's own namespace lib
```

`mergedLib` goes to `nixosSystem` and `darwinSystem` as `specialArgs.lib`. Standalone
`homeConfigurations` also get it as `lib`. Home-manager's `lib.hm` extension is added
back so its internals keep working:
`homeLib = mergedLib // { hm = inputs.home-manager.lib.hm; }`. This replaces the old
`purrLib` argument. There are no
`_module.args.lib` overrides.

Bridged homes (home-manager inside a system) do not get a `lib` override. Home-manager
evaluates them through `types.submoduleWith`, and overriding `lib` there breaks its
internal module collection (`lib.hm` disappears). They keep home-manager's own extended
lib. The merged namespace lib is exposed in both standalone and bridged homes as
`purr.lib` (`homeLib`, the merged lib plus `hm`), so `purr.lib.<namespace>.xxx` works
everywhere. Standalone homes also get it as `lib`.

> TODO: this `purr.lib` workaround exists because of a home-manager regression. With
> `types.submoduleWith`, overriding `lib` through `extraSpecialArgs` breaks its internal
> module collection (`lib.hm` goes missing during option collection). Once that is fixed
> upstream, bridged homes can get `lib = homeLib` directly and `purr.lib` can be
> dropped.

## Input roles (`inputsFor` and meta role keys)

purr lets different hosts use different inputs, for example a second nixpkgs or a
different home-manager. The pipeline has two stages and stays pure and lazy:

1. `inputsFor` (`mkFlake { inputsFor }` or `purr.inputsFor`): a function
   `{ inputs, ... } -> inputs'`, or a plain attrset, that filters or replaces the raw
   flake inputs and produces the effective inputs. The default is the identity. This is
   internal: it changes which input purr uses for pkgs, system configs, home configs,
   and the merged lib base. Modules always receive the raw flake inputs.
2. Host meta role keys: `meta.roles.<role>` (for example `meta.roles.nixpkgs`) names a
   key in the effective inputs to use for that host. The role names (`nixpkgs`,
   `home-manager`, `nix-darwin`) live under `meta.roles` so they don't collide with
   custom meta keys. `buildSystemConfigs` and `buildHomeConfigs` resolve them through
   `lib/resolveInput.nix`. A host sets the key and purr builds from that input; `null`
   or an absent key falls back to the conventional key (`nixpkgs`,
   `home-manager`/`homeManager`, `nix-darwin`/`darwin`) in the effective inputs.

Priority is: host meta key, then the conventional effective-input key, then the raw
input. Meta is static and resolved before config evaluation, so role resolution is a
simple string lookup with no recursion.

Places that use `effectiveInputs` and role resolution:

- `nixosSystem` (linux host):
  `effectiveInputs.<meta.roles.nixpkgs or "nixpkgs">.lib.nixosSystem`
- `darwinSystem` (darwin host):
  `effectiveInputs.<meta.roles.nix-darwin or auto>.lib.darwinSystem`
- home-manager bridge: `effectiveInputs.<meta.roles."home-manager" or auto>`
- standalone homes: pkgs imported from the linked system's role (through
  `systemMeta.nixpkgs`), or the effective-input default
- per-system pkgs (packages/shells/checks/apps) and hydraJobs `systemPkgs`:
  `effectiveInputs.nixpkgs`
- merged lib base: `effectiveInputs.nixpkgs.lib`

The merged lib handed to a system's modules follows that host's own nixpkgs.
`perHostLib` re-merges the host's resolved nixpkgs lib with the flake's namespace lib,
so lib-derived metadata (`system.nixos.revision`, ...) and `lib`/`pkgs` stay consistent
when the host switches nixpkgs. For homes, the per-host replacement only shows up
through `purr.lib`. Home-manager's own evaluation lib stays on the caller-provided
merged lib (matching home-manager's pinned nixpkgs), which keeps its internals stable.
Only the top-level `flake.lib` export stays the global namespace lib. When a host's
nixpkgs is missing (or is a non-nixpkgs mock), the lib falls back to the caller-provided
merged lib.

Referencing an input that is missing from the effective inputs throws a clear error
(`role input '<key>' is not a key of the effective inputs (the inputsFor result)`). Keep
every input hosts may reference inside `inputsFor`.

## Host metadata (meta)

Hosts can carry metadata that purr reads at flake-evaluation time (cheap, no
nixpkgs/system eval) and exposes to the host's modules as `purr.meta`.

### Sources (merged in increasing priority)

1. Auto-generated: `name`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`,
   `system`, `homes` (derived from the host's directory path and matched homes).
2. `meta.nix` next to the host's `systems/<arch>-<format>/<name>/default.nix`. A plain
   attrset, or a function that receives `inputs`, `lib`, `namespace`, `extraArgs`,
   `host`, `name`, `system`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`,
   `homes`, and so on. All arguments are lazily bound, so cheap conditionals like
   `if inputs ? nix-darwin then ...` are free.
3. Flake config: `hosts.<name>.meta` in `mkFlake`, or `purr.hosts.<name>.meta` in
   flake-parts. Deep-merged on top of `meta.nix`, with leaves winning.

### Reserved keys

The auto-generated keys above cannot be overridden. Setting one in any user meta source
emits a warning and the value is dropped, so the auto structure always wins. Referencing
an unknown host through `hosts.<name>.meta` is an error.

### Behaviour keys purr consumes

- `images`: list of image formats, driving the `flake.images` / hydraJobs `images`
  output (`config.system.build.images.<format>`).
- `deployable`: whether the host is exposed as a
  `nixosConfigurations`/`darwinConfigurations` output. Defaults to `true` when
  `images == []` or the host is darwin. A host with `images` is image-only by default (excluded
  from config outputs and config hydraJobs groups).
- `roles`: input role keys (see "Input roles" above) that map a role name (`nixpkgs`,
  `home-manager`, `nix-darwin`) to a key of the effective inputs to build this host
  from. For example, `meta.roles.nixpkgs = "nixpkgs-stable"`.

Everything else in the merged meta is a free-form custom key exposed as
`purr.meta.<key>` for user automation.

### `purr` injection

The merged meta (always containing the 8 auto keys plus normalized `images` and the
derived `deployable`) is passed to host modules as `purr.meta` in
`nixosSystem`/`darwinSystem` `specialArgs` and the home-manager bridge
`extraSpecialArgs`. There are no top-level purr shortcuts; everything about the host
lives under `purr.meta.*`.

Every discovered host is registered in a registry built by `buildSystemRegistry` and
exposed as `purr.systemMetas` (`<hostName> -> <that host's merged meta>`, including
self, across all arch-formats). The registry holds pure metadata, never config values.

- System modules: `purr = { meta, systemMetas }`.
- Home modules (standalone and bridged): `purr = { meta, systemMeta, systemMetas, lib }`
  where `meta` is `{ user, host, system, arch, archFormat, format, isDarwin, isLinux }`,
  `systemMeta` is the merged meta of the system named by the home's host (or `null` when
  no matching system exists), `systemMetas` is the same registry, and `lib` is the
  merged namespace lib (see the bridged-home note above). Home configs can be built
  independently of systems, so an empty registry gives `systemMetas = { }` and
  `systemMeta = null`.

## Testing

Add tests for every feature or fix, and run `nix flake check`.

Tests live in `tests/` and use a custom runner (`tests/runner.nix`), not
`lib.debug.runTests` (which skips groups whose names don't start with "test", the reason
the old suite always looked green). The runner runs every registered test and reports
exceptions as failures.

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

A test passes when `expr == expected` (deep structural equality). A throwing `expr` is
reported as a failure, not a crash.

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

Drop a new file `tests/unit/test-<name>.nix` (or `tests/integration/test-<name>.nix`).
`list-tests.nix` discovers it automatically, and the shell runner, the Nix report, and
the `purr-tests` check all pick it up. No registration is needed.

### Running the tests

```bash
# Via Nix: the check derivation writes the full report into its result
nix build .#checks.x86_64-linux.purr-tests && cat result   # all green -> report
nix log .#checks.x86_64-linux.purr-tests                    # failures -> report in log
nix flake check                                            # CI gate (pre-commit + purr-tests)

# Via the dev shell: a live per-test runner
nix develop --command purr-test
# or directly (no dev shell)
tests/run-tests.sh

# Fast iteration on one file
nix eval --json --impure --expr 'let
  lib = (builtins.getFlake "github:nix-community/nixpkgs.lib").lib;
  runner = import ./tests/runner.nix { inherit lib; };
  t = import ./tests/unit/test-configs.nix { inherit lib; };
in builtins.map (f: f.group + "." + f.testName) (runner.runTestModule t)'
```

`report.nix` computes the full report in a single pure evaluation, so the check
derivation is fast. `run-tests.sh` evaluates each test individually instead (Nix is
lazy, so a single eval cannot stream results), which gives live per-test progress.

### Integration tests

The integration tests run `mkFlake` on `tests/integration/project` and verify every
output. `nixosSystem`, `darwinSystem`, and `homeManagerConfiguration` are mocked to
evaluate their module lists through the real `lib.evalModules`, with minimal shim
options declared in `harness.nix`. Generated system and home configs are therefore
evaluated for real: auto-injection, the namespace bridge
(`purr.users.<name>.homeConfig`), linked homes, image-only hosts, by-name packages,
hydraJobs mirroring, and more are asserted against evaluation, not string inspection.

### Gotchas

- Don't pass a path to a nonexistent directory into a function that calls
  `builtins.readDir`. Nix's path-existence error is not caught by `builtins.tryEval` and
  crashes the run.
- Don't deep-compare `lib` or large attrsets with `==`; it forces huge lazy values.
  Compare markers or keys instead.
- Don't compare functions with `==`; coerce with `builtins.isFunction`,
  `builtins.attrNames`, or `toString` first.
- `imagesFromConfigs` takes the `imageRecipes` shape:
  `{ host = { system; images; cfg = { config = { system.build.images }; }; }; }`,
  not the `nixosConfigurations` shape.
- Host metadata comes from `meta.nix` or `hosts.<name>.meta`, never from the host
  module. Host modules must not (and need not) declare `purr.images` or
  `purr.deployable`.
