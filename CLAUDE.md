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

For module-arg tests, use `lib.evalModules` with `specialArgs = { pkgs = { ... }; }` to simulate module evaluation. `builtins.tryEval` catches thrown asserts — use `assert` for arg validation.
