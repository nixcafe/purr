# Compute the full test report in a single pure evaluation.
#
#   nix eval --json --impure --expr '
#     let lib = (builtins.getFlake "github:nix-community/nixpkgs.lib").lib;
#     in import ./tests/report.nix { inherit lib; }'
#
# Returns `{ failedCount; reportText; records; }`.  The `purr-tests` check
# derivation writes `reportText` into its `$out` and fails the build when
# `failedCount > 0`, so:
#
#   - tests pass:  nix build .#checks.x86_64-linux.purr-tests && cat result
#   - tests fail:  nix log <purr-tests-drv>   (build fails with the report)
{ lib }:
let
  inherit (lib)
    concatMap
    concatStringsSep
    filter
    length
    map
    toJSON
    ;

  runner = import ./runner.nix {
    inherit lib;
  };

  tests = import ./list-tests.nix {
    inherit lib;
  };

  recordOf =
    t:
    let
      m = import (./. + "/${t.file}") {
        inherit lib;
      };
      failures = runner.runTest t.group t.test m.${t.group}.tests.${t.test};
    in
    {
      inherit (t) file group test;
      status = if failures == [ ] then "PASS" else "FAIL";
      failure = if failures == [ ] then null else builtins.head failures;
    };

  records = map recordOf tests;
  failed = filter (r: r.status == "FAIL") records;
  failedCount = length failed;
  passedCount = length records - failedCount;

  describe =
    r:
    if r.status == "PASS" then
      "PASS  ${r.file} :: ${r.group} :: ${r.test}"
    else
      let
        f = r.failure;
        detail =
          if f ? error then
            "      error: ${f.error}"
          else
            "      expected: ${toJSON f.expected}\n      result:   ${toJSON f.result}";
      in
      "FAIL  ${r.file} :: ${r.group} :: ${r.test}\n${detail}";

  reportText =
    concatStringsSep "\n" (map describe records)
    + "\n\n[summary] ${toString passedCount} passed, ${toString failedCount} failed, ${toString (length records)} total";
in
{
  inherit failedCount reportText records;
}
