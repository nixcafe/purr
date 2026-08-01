# Custom test runner for purr.
#
# Unlike `lib.debug.runTests` (which silently skips any test whose group name
# does not start with "test"), this runner executes EVERY registered test,
# catches exceptions (so a throwing `expr` is reported as a failure instead of
# aborting the whole run), and produces a structured failure list.
#
# A test module has the shape:
#
#   {
#     groupName = {
#       tests = {
#         "test name" = {
#           expr = <expression>;
#           expected = <value>;
#         };
#       };
#     };
#   }
#
# The result is a list of failures.  Empty list means all tests passed.
# Each failure is:
#
#   { group = <groupName>; test = <testName>; expected; result; }
#   { group = <groupName>; test = <testName>; error = <exception message>; }
{ lib }:
let
  inherit (lib)
    concatMap
    mapAttrsToList
    optional
    ;

  # Run a single test, returning either [] or one failure.
  runTest =
    group: testName: t:
    let
      outcome = builtins.tryEval (t.expr == t.expected);
    in
    if !outcome.success then
      [
        {
          inherit group testName;
          error = "evaluation threw an exception (see --show-trace)";
        }
      ]
    else if outcome.value then
      [ ]
    else
      [
        {
          inherit group testName;
          inherit (t) expected;
          result = t.expr;
        }
      ];

  # Run a whole group: { tests = { ... }; }
  runGroup =
    group: groupModule:
    concatMap (testName: runTest group testName groupModule.tests.${testName}) (
      builtins.attrNames groupModule.tests
    );

  # Run every group returned by a test module and flatten the failures.
  runTestModule =
    testModule: concatMap (group: runGroup group testModule.${group}) (builtins.attrNames testModule);
in
{
  inherit runGroup runTest runTestModule;
}
