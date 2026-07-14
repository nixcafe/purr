# Tests for namespace wrapping utilities in lib/namespacedModules.nix
{
  lib,
}:
let
  namespacedModules = import ../lib/namespacedModules.nix;
in
{
  deepMapAttrs = {
    tests = {
      "maps over nested attrsets" = {
        expr = namespacedModules.deepMapAttrs (x: x + 1) {
          a = {
            b = 1;
            c = 2;
          };
        };
        expected = {
          a = {
            b = 2;
            c = 3;
          };
        };
      };

      "treats functions as leaves" = {
        expr =
          let
            f = x: x + 1;
            result = namespacedModules.deepMapAttrs (_: "mapped") {
              a.b = f;
            };
          in
          result.a.b;
        expected = "mapped";
      };

      "treats paths as leaves" = {
        expr =
          let
            result = namespacedModules.deepMapAttrs (_: "mapped") {
              a.b = ./default.nix;
            };
          in
          result.a.b;
        expected = "mapped";
      };

      "handles empty attrs" = {
        expr = namespacedModules.deepMapAttrs (x: x) { };
        expected = { };
      };

      "handles deeply nested structure" = {
        expr = namespacedModules.deepMapAttrs (_: "leaf") {
          a = {
            b = {
              c = {
                d = 1;
              };
            };
          };
        };
        expected = {
          a = {
            b = {
              c = {
                d = "leaf";
              };
            };
          };
        };
      };

      "treats scalar values as leaf" = {
        expr = namespacedModules.deepMapAttrs (x: x + 1) 42;
        expected = 43;
      };

      "treats flat single-level attrs correctly" = {
        expr = namespacedModules.deepMapAttrs (_: "mapped") {
          a = 1;
          b = 2;
        };
        expected = {
          a = "mapped";
          b = "mapped";
        };
      };

      "handles null values" = {
        expr = namespacedModules.deepMapAttrs (x: if x == null then 0 else x) {
          a = null;
          b = 1;
        };
        expected = {
          a = 0;
          b = 1;
        };
      };
    };
  };

  wrapModuleSet = {
    tests = {
      "wraps all leaf modules in nested tree" = {
        expr =
          let
            modA = _: {
              config.a = true;
            };
            modB = _: {
              config.b = true;
            };
            wrapped = namespacedModules.wrapModuleSet "ns" {
              group1.mod1 = modA;
              group1.mod2 = modB;
              group2.mod3 = modA;
            };
            result = lib.evalModules {
              modules = [
                wrapped.group1.mod1
                wrapped.group1.mod2
              ];
            };
          in
          result.config.ns.a && result.config.ns.b;
        expected = true;
      };

      "null namespace returns modules unchanged" = {
        expr =
          let
            mod = _: { };
            wrapped = namespacedModules.wrapModuleSet null {
              a.b = mod;
            };
          in
          wrapped.a.b == mod;
        expected = true;
      };

      "empty attrs returns empty attrs" = {
        expr = namespacedModules.wrapModuleSet "ns" { };
        expected = { };
      };

      "flat single-level attrset" = {
        expr =
          let
            mod = _: { };
            wrapped = namespacedModules.wrapModuleSet "ns" { a = mod; };
            result = lib.evalModules {
              modules = [ wrapped.a ];
            };
          in
          result.config ? ns;
        expected = true;
      };
    };
  };
}
