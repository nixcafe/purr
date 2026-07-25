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

Tests use `lib.debug.runTests` (from nixpkgs-lib). Each test is `{ expr; expected; }`. Returned list of failures — empty = all pass.

### How to add a test

1. Create `tests/<name>.nix`:
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
   <name> = import ./<name>.nix { inherit lib; };
   ```
   Then add to `failures`:
   ```nix
   ++ (runGroup "<name>.<group>" <name>.<group>)
   ```
3. `git add tests/<name>.nix && nix flake check`

### Integration testing with the demo

The `tests/demo/` directory is a standalone flake that exercises all
purr features end-to-end (modules, lib, packages, shells, checks,
overlays, templates, apps, systems, homes, namespace bridge).

```bash
cd tests/demo && nix flake check
```

### Fixtures

`tests/fixtures/` provides minimal directory trees for module-discovery
unit tests.  Each `default.nix` contains only `{ }`.  Keep fixtures this
small — they are Git-tracked for reproducibility.

For module-arg tests, use `lib.evalModules` with `specialArgs = { pkgs = { ... }; }` to simulate module evaluation. For mkFlake integration tests, mock `nixosSystem` / `homeManagerConfiguration` to avoid full nixpkgs evaluation — see `tests/mkFlake-systems.nix` for examples.
