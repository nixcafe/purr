# `vendor/flake-compat`

Purr vendors a minimal [flake-compat] to load the dev flake without
adding `nixpkgs` as a transitive input to consumers.

Source: https://github.com/NixOS/flake-compat
License: MIT (see COPYING)

## Why vendor?

- Dependency is tiny (~120 lines)
- Avoids adding dev-only inputs (nixpkgs, etc.) to consumer lock files
- Same pattern used by flake-parts in their `partitions` module
- Most users are unaffected (only impacts `devShells`/`checks` access)

[flake-compat]: https://github.com/NixOS/flake-compat
