# Unit tests for lib/namespacedModules.nix — namespace wrapping of modules.
{ lib }:
let
  nsm = import ../../lib/namespacedModules.nix;
in
{
  deepMapAttrs = {
    tests = {
      "maps over nested attrsets" = {
        expr = nsm.deepMapAttrs (x: x + 1) {
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
        expr = nsm.deepMapAttrs (_: "mapped") {
          a.b = x: x;
        };
        expected = {
          a.b = "mapped";
        };
      };
      "treats paths as leaves" = {
        expr = nsm.deepMapAttrs (_: "mapped") {
          a.b = ./default.nix;
        };
        expected = {
          a.b = "mapped";
        };
      };
      "treats module attrsets as leaves" = {
        expr = nsm.deepMapAttrs (_: "mapped") {
          a = {
            imports = [ ];
          };
        };
        expected = {
          a = "mapped";
        };
      };
      "handles empty attrs" = {
        expr = nsm.deepMapAttrs (x: x) { };
        expected = { };
      };
      "handles deeply nested structure" = {
        expr = nsm.deepMapAttrs (_: "leaf") {
          a.b.c.d = 1;
        };
        expected = {
          a.b.c.d = "leaf";
        };
      };
      "treats scalar values as leaves" = {
        expr = nsm.deepMapAttrs (x: x + 1) 42;
        expected = 43;
      };
      "handles null values" = {
        expr = nsm.deepMapAttrs (x: if x == null then 0 else x) {
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

  wrapModule = {
    tests = {
      "wraps a function module with namespace injection" = {
        expr =
          let
            mod =
              {
                lib,
                namespace,
                ...
              }:
              {
                options.${namespace}.marker = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };
                config.${namespace}.marker = "wrapped";
              };
            wrapped = nsm.wrapModule "ns" null { } mod;
            result = lib.evalModules {
              modules = [ wrapped ];
            };
          in
          result.config.ns.marker;
        expected = "wrapped";
      };
      "module receives namespace and real lib with namespace injected" = {
        expr =
          let
            importedPurrLib = {
              helper = "value";
            };
            mod =
              {
                lib,
                namespace,
                ...
              }:
              {
                options.${namespace}.hasNsLib = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                };
                config.${namespace}.hasNsLib = lib.${namespace}.helper or null;
              };
            wrapped = nsm.wrapModule "ns" importedPurrLib { } mod;
            result = lib.evalModules {
              modules = [ wrapped ];
            };
          in
          result.config.ns.hasNsLib;
        expected = "value";
      };
      "module receives pkgs from specialArgs" = {
        expr =
          let
            mod =
              {
                lib,
                pkgs,
                namespace,
                ...
              }:
              {
                options.${namespace}.hasPkgs = lib.mkOption {
                  type = lib.types.bool;
                };
                config.${namespace}.hasPkgs = pkgs != null;
              };
            wrapped = nsm.wrapModule "ns" null { } mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config.ns.hasPkgs;
        expected = true;
      };
      "module receives args provided only via _module.args" = {
        expr =
          let
            mod =
              {
                lib,
                user,
                ...
              }:
              {
                options.value = lib.mkOption {
                  type = lib.types.str;
                };
                config.value = user;
              };
            wrapped = nsm.wrapModule "ns" null { } mod;
            result = lib.evalModules {
              modules = [
                {
                  _module.args.user = "alice";
                }
                wrapped
              ];
            };
          in
          result.config.value;
        expected = "alice";
      };
      "attrset module with options is wrapped and importable" = {
        expr =
          let
            mod = {
              options.${"x"} = { };
            };
            wrapped = nsm.wrapModule "ns" null { } mod;
          in
          (wrapped ? options) && (wrapped ? imports);
        expected = true;
      };
      "path modules get wrapped into functions" = {
        expr =
          let
            wrapped = nsm.wrapModule "ns" null { } ./fixtures/empty-module.nix;
          in
          builtins.isFunction wrapped;
        expected = true;
      };
      "non-module values pass through unchanged" = {
        expr =
          let
            value = {
              plain = 1;
            };
          in
          nsm.wrapModule "ns" null { } value;
        expected = {
          plain = 1;
        };
      };
      "module receives defining flake's inputs, not consumer's" = {
        expr =
          let
            mod =
              {
                inputs,
                lib,
                ...
              }:
              {
                options.value = lib.mkOption {
                  type = lib.types.str;
                };
                config.value = inputs.fromDefiningFlake;
              };
            # Defining flake declares `fromDefiningFlake`.
            wrapped = nsm.wrapModule "ns" null {
              fromDefiningFlake = "defining";
            } mod;
            result = lib.evalModules {
              modules = [
                # Consumer tries to override inputs.
                {
                  _module.args.inputs = {
                    fromDefiningFlake = "consumer";
                  };
                }
                wrapped
              ];
            };
          in
          result.config.value;
        expected = "defining";
      };
    };
  };

  wrapModuleSet = {
    tests = {
      "null namespace returns modules unchanged" = {
        expr =
          let
            modules = {
              a.b = {
                imports = [ ];
              };
            };
          in
          nsm.wrapModuleSet null null { } modules;
        expected = {
          a.b = {
            imports = [ ];
          };
        };
      };
      "non-null namespace wraps every leaf module" = {
        expr =
          let
            mod =
              {
                lib,
                namespace,
                ...
              }:
              {
                options.${namespace}.leaf = lib.mkOption {
                  type = lib.types.bool;
                };
                config.${namespace}.leaf = true;
              };
            wrapped = nsm.wrapModuleSet "ns" null { } {
              group1.m1 = mod;
              group2.m2 = mod;
            };
            result = lib.evalModules {
              modules = [
                wrapped.group1.m1
                wrapped.group2.m2
              ];
            };
          in
          result.config.ns.leaf;
        expected = true;
      };
      "empty attrs returns empty attrs" = {
        expr = nsm.wrapModuleSet "ns" null { } { };
        expected = { };
      };
      "module receives namespace and pkgs through wrapping" = {
        expr =
          let
            mod =
              {
                lib,
                pkgs,
                namespace,
                ...
              }:
              {
                options.${namespace}.ok = lib.mkOption {
                  type = lib.types.bool;
                };
                config.${namespace}.ok = pkgs != null;
              };
            wrapped = nsm.wrapModuleSet "test-ns" null { } {
              a.b = mod;
            };
            result = lib.evalModules {
              modules = [ wrapped.a.b ];
              specialArgs = {
                pkgs = { };
              };
            };
          in
          result.config."test-ns".ok;
        expected = true;
      };
    };
  };
}
