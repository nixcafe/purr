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
