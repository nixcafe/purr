# Run a single test case and print its failure as JSON.
#
#   nix eval --impure \
#     --argstr file "unit/test-attrs.nix" \
#     --argstr group "optionalAttrs" \
#     --argstr test "true returns attrs unchanged" \
#     --expr 'import ./run-one.nix { ... }'
#
# Prints `[]` when the test passes, or a JSON failure record otherwise.
{
  lib,
  file,
  group,
  test,
}:
let
  runner = import ./runner.nix {
    inherit lib;
  };
  m = import (./. + "/${file}") {
    inherit lib;
  };
in
builtins.toJSON (runner.runTest group test m.${group}.tests.${test})
