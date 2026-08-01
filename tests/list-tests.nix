# Enumerate every test case in the suite.
#
# Returns a list of `{ file; group; test; }` where `file` is relative to the
# `tests/` directory.
#
# Discovery is automatic: every `test-*.nix` file under `tests/unit/` and
# `tests/integration/` is picked up, so adding a new test file is as simple as
# dropping it in one of those directories — the shell runner, the Nix report,
# and the check derivation all pick it up automatically.
{ lib }:
let
  base = ./.;

  scan =
    dir:
    let
      dirPath = base + "/${dir}";
      names = builtins.attrNames (builtins.readDir dirPath);
      testFiles = builtins.filter (n: lib.hasPrefix "test-" n && lib.hasSuffix ".nix" n) names;
    in
    map (f: "${dir}/${f}") testFiles;

  files = (scan "unit") ++ (scan "integration");

  testsOf =
    file:
    let
      m = import (base + "/${file}") {
        inherit lib;
      };
    in
    lib.concatMap (
      group: lib.map (test: { inherit file group test; }) (builtins.attrNames m.${group}.tests)
    ) (builtins.attrNames m);
in
builtins.concatMap testsOf files
