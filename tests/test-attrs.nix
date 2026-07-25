# Tests for lib/attrs.nix
{ lib }:
let
  attrs = import ../lib/attrs.nix;
in
{
  optionalAttrs = {
    tests = {
      "true returns attrs" = {
        expr = attrs.optionalAttrs true { a = 1; };
        expected = {
          a = 1;
        };
      };
      "false returns empty" = {
        expr = attrs.optionalAttrs false { a = 1; };
        expected = { };
      };
    };
  };
}
