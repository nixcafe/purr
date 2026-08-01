# Unit tests for lib/attrs.nix
{ lib }:
let
  attrs = import ../../lib/attrs.nix;
in
{
  optionalAttrs = {
    tests = {
      "true returns attrs unchanged" = {
        expr = attrs.optionalAttrs true {
          a = 1;
          b = "x";
        };
        expected = {
          a = 1;
          b = "x";
        };
      };
      "false returns empty set" = {
        expr = attrs.optionalAttrs false {
          a = 1;
        };
        expected = { };
      };
      "empty attrs preserved when true" = {
        expr = attrs.optionalAttrs true { };
        expected = { };
      };
      "result is a fresh attrset (does not mutate input)" = {
        expr =
          let
            input = {
              a = 1;
            };
            output = attrs.optionalAttrs true input;
          in
          output == input;
        expected = true;
      };
    };
  };
}
