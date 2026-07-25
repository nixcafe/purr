# Tests for lib/namespacedModules.nix
{ lib }:
let
  nsm = import ../lib/namespacedModules.nix;
in
{
  # ---- deepMapAttrs ----
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
        expr =
          let
            f = x: x + 1;
            result = nsm.deepMapAttrs (_: "mapped") { a.b = f; };
          in
          result.a.b;
        expected = "mapped";
      };
      "treats paths as leaves" = {
        expr =
          let
            result = nsm.deepMapAttrs (_: "mapped") { a.b = ./default.nix; };
          in
          result.a.b;
        expected = "mapped";
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
      "treats scalar values as leaf" = {
        expr = nsm.deepMapAttrs (x: x + 1) 42;
        expected = 43;
      };
      "treats flat single-level attrs correctly" = {
        expr = nsm.deepMapAttrs (_: "mapped") {
          a = 1;
          b = 2;
        };
        expected = {
          a = "mapped";
          b = "mapped";
        };
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

  # ---- wrapModule ----
  wrapModule = {
    tests = {
      "receives pkgs, config, lib, namespace" = {
        expr =
          let
            mod =
              {
                pkgs,
                lib,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasPkgs = pkgs != null;
                config.${namespace}.hasLib = lib != null;
                config.${namespace}.nsValue = namespace;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".hasPkgs;
        expected = true;
      };
      "config passed by module system is not null" = {
        expr =
          let
            mod =
              {
                config,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasConfig = config != null;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = { };
            };
          in
          result.config."test-ns".hasConfig;
        expected = true;
      };
      "lib passed by module system is not null" = {
        expr =
          let
            mod =
              {
                lib,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasLib = lib != null;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = { };
            };
          in
          result.config."test-ns".hasLib;
        expected = true;
      };
      "namespace injected by wrapModule is correct" = {
        expr =
          let
            mod =
              {
                namespace,
                ...
              }:
              {
                config.${namespace}.nsValue = namespace;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = { };
            };
          in
          result.config."test-ns".nsValue;
        expected = "test-ns";
      };
      "different namespace produces correct value" = {
        expr =
          let
            mod =
              {
                namespace,
                ...
              }:
              {
                config.${namespace}.nsValue = namespace;
              };
            wrapped = nsm.wrapModule "cattery" mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = { };
            };
          in
          result.config.cattery.nsValue;
        expected = "cattery";
      };
      "module without namespace param does not crash" = {
        expr =
          let
            mod = { pkgs, ... }: { config.noNs = pkgs != null; };
            wrapped = nsm.wrapModule "test-ns" mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config.noNs;
        expected = true;
      };
      "namespace override when specialArgs already has namespace" = {
        expr =
          let
            mod =
              {
                namespace,
                ...
              }:
              {
                config.${namespace}.nsOk = namespace != null;
              };
            wrapped = nsm.wrapModule "second-ns" mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                namespace = "first-ns";
              };
            };
          in
          result.config."second-ns".nsOk;
        expected = true;
      };
    };
  };

  # ---- wrapWithLib (namespace lib injection) ----
  wrapWithLib = {
    tests = {
      "_module.args.lib does not strip pkgs" = {
        expr =
          let
            mod =
              {
                pkgs,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasPkgs = pkgs != null;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            customLib = lib // {
              testMarker = true;
            };
            withLib = {
              imports = [
                { _module.args.lib = customLib; }
                wrapped
              ];
            };
            result = lib.evalModules {
              modules = [ withLib ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".hasPkgs;
        expected = true;
      };
      "_module.args.lib does not strip config" = {
        expr =
          let
            mod =
              {
                config,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasConfig = config != null;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            customLib = lib // {
              testMarker = true;
            };
            withLib = {
              imports = [
                { _module.args.lib = customLib; }
                wrapped
              ];
            };
            result = lib.evalModules {
              modules = [ withLib ];
              specialArgs = { };
            };
          in
          result.config."test-ns".hasConfig;
        expected = true;
      };
      "custom lib is propagated via _module.args" = {
        expr =
          let
            checkModule =
              {
                lib,
                ...
              }:
              {
                config.testLibMarker = lib.testMarker or false;
              };
            customLib = lib // {
              testMarker = true;
            };
            result = lib.evalModules {
              modules = [
                { _module.args.lib = customLib; }
                checkModule
              ];
            };
          in
          result.config.testLibMarker;
        expected = true;
      };
      "namespace is preserved with _module.args.lib override" = {
        expr =
          let
            mod =
              {
                namespace,
                ...
              }:
              {
                config.${namespace}.nsValue = namespace;
              };
            wrapped = nsm.wrapModule "test-ns" null mod;
            customLib = lib // {
              testMarker = true;
            };
            withLib = {
              imports = [
                { _module.args.lib = customLib; }
                wrapped
              ];
            };
            result = lib.evalModules {
              modules = [ withLib ];
              specialArgs = { };
            };
          in
          result.config."test-ns".nsValue;
        expected = "test-ns";
      };
      "module with explicit { pkgs, config, lib, namespace, ... } works" = {
        expr =
          let
            mod =
              {
                pkgs,
                config,
                lib,
                namespace,
                ...
              }:
              {
                config.${namespace} = {
                  pkgsOk = pkgs != null;
                  configOk = config != null;
                  libOk = lib != null;
                  nsOk = namespace != null;
                };
              };
            wrapped = nsm.wrapModule "test-ns" mod;
            customLib = lib // {
              testMarker = true;
            };
            withLib = {
              imports = [
                { _module.args.lib = customLib; }
                wrapped
              ];
            };
            result = lib.evalModules {
              modules = [ withLib ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
            cfg = result.config."test-ns";
          in
          cfg.pkgsOk && cfg.configOk && cfg.libOk && cfg.nsOk;
        expected = true;
      };
      "wrapModule passes lib namespace when importedPurrLib set" = {
        expr =
          let
            customLib = {
              helper = "value";
            };
            mod =
              {
                lib,
                namespace,
                ...
              }:
              {
                config.${namespace}.hasNs = lib.${namespace}.helper or "missing";
              };
            wrapped = nsm.wrapModule "test-ns" customLib mod;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = { };
            };
          in
          result.config."test-ns".hasNs;
        expected = "value";
      };
    };
  };

  # ---- wrapModuleSet ----
  wrapModuleSet = {
    tests = {
      "wraps all leaf modules in nested tree" = {
        expr =
          let
            modA = _: { config.a = true; };
            modB = _: { config.b = true; };
            wrapped = nsm.wrapModuleSet "ns" null {
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
            wrapped = nsm.wrapModuleSet null null { a.b = mod; };
          in
          wrapped.a.b == mod;
        expected = true;
      };
      "empty attrs returns empty attrs" = {
        expr = nsm.wrapModuleSet "ns" null { };
        expected = { };
      };
      "flat single-level attrset" = {
        expr =
          let
            wrapped = nsm.wrapModuleSet "ns" null { a = _: { }; };
            result = lib.evalModules {
              modules = [ wrapped.a ];
            };
          in
          result.config ? ns;
        expected = true;
      };
      "nested module receives namespace and pkgs" = {
        expr =
          let
            mod =
              {
                pkgs,
                namespace,
                ...
              }:
              {
                config.${namespace} = {
                  pkgsOk = pkgs != null;
                  nsOk = namespace != null;
                };
              };
            wrapped = nsm.wrapModuleSet "test-ns" null { a.b = mod; };
            result = lib.evalModules {
              modules = [ wrapped.a.b ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
            cfg = result.config."test-ns";
          in
          cfg.pkgsOk && cfg.nsOk;
        expected = true;
      };
    };
  };

  nullNamespace = {
    tests = {
      "null namespace passes modules unchanged" = {
        expr =
          let
            mod = _: { };
            wrapped = nsm.wrapModuleSet null null { a = mod; };
          in
          wrapped.a == mod;
        expected = true;
      };
    };
  };
}
