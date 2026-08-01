# Test runner entry point for purr.
#
#   import ./tests/default.nix { inherit lib; }
#
# where `lib` is nixpkgs-lib.  Returns the flat list of test failures
# (empty = all pass).  Every `test-*.nix` under `tests/unit/` and
# `tests/integration/` is auto-discovered — no registration needed when adding
# a new test file.
#
# For a full per-test report (with PASS/FAIL lines), see `report.nix`.
{ lib }:
let
  runner = import ./runner.nix {
    inherit lib;
  };

  tests = import ./list-tests.nix {
    inherit lib;
  };

  files = lib.unique (map (t: t.file) tests);
in
lib.concatMap (file: runner.runTestModule (import (./. + "/${file}") { inherit lib; })) files
