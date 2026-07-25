# Tests for module argument passing.
# Verifies that { pkgs, config, lib, namespace, ... } are correctly
# injected into NixOS-type modules via wrapModule and wrapWithLib.
{
  lib,
}:
let
  namespacedModules = import ../lib/namespacedModules.nix;

  mkMockModule =
    extraAssert:
    {
      pkgs,
      config,
      lib,
      namespace,
      ...
    }:
    assert extraAssert;
    assert pkgs != null;
    assert config != null;
    assert lib != null;
    {
      config.${namespace} = {
        hasPkgs = pkgs != null;
        hasConfig = config != null;
        hasLib = lib != null;
        namespaceValue = namespace;
      };
    };

  recordModule =
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
in
{
  wrapModule = {
    tests = {
      "receives pkgs, config, lib, namespace" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
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
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".hasConfig;
        expected = true;
      };

      "lib passed by module system is not null" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".hasLib;
        expected = true;
      };

      "namespace injected by wrapModule is correct" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".namespaceValue;
        expected = "test-ns";
      };

      "different namespace produces correct value" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "cattery" (mkMockModule true);
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config.cattery.namespaceValue;
        expected = "cattery";
      };
    };
  };

  wrapWithLib = {
    tests = {
      "_module.args.lib does not strip pkgs" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
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
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
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

      "namespace is preserved with _module.args.lib" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" null (mkMockModule true);
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
          result.config."test-ns".namespaceValue;
        expected = "test-ns";
      };

      "module with explicit { pkgs, config, lib, namespace, ... }" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "test-ns" recordModule;
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
          result.config."test-ns".pkgsOk
          && result.config."test-ns".configOk
          && result.config."test-ns".libOk
          && result.config."test-ns".nsOk;
        expected = true;
      };
    };
  };

  wrapModuleSet = {
    tests = {
      "nested module receives namespace" = {
        expr =
          let
            modules = {
              a = {
                b = recordModule;
              };
            };
            wrapped = namespacedModules.wrapModuleSet "test-ns" null modules;
            result = lib.evalModules {
              modules = [ wrapped.a.b ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".nsOk;
        expected = true;
      };

      "nested module receives pkgs" = {
        expr =
          let
            modules = {
              a = {
                b = recordModule;
              };
            };
            wrapped = namespacedModules.wrapModuleSet "test-ns" null modules;
            result = lib.evalModules {
              modules = [ wrapped.a.b ];
              specialArgs = {
                pkgs = {
                  mock = true;
                };
              };
            };
          in
          result.config."test-ns".pkgsOk;
        expected = true;
      };
    };
  };

  nullNamespace = {
    tests = {
      "null namespace passes modules unchanged" = {
        expr =
          let
            wrapped = namespacedModules.wrapModuleSet null null {
              a = recordModule;
            };
          in
          wrapped.a == recordModule;
        expected = true;
      };
    };
  };

  wrapModuleEdgeCases = {
    tests = {
      "module without namespace param does not crash" = {
        expr =
          let
            mod = { pkgs, ... }: {
              config.noNs = pkgs != null;
            };
            wrapped = namespacedModules.wrapModule "test-ns" mod;
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

      "namespace override when args already has namespace" = {
        expr =
          let
            wrapped = namespacedModules.wrapModule "second-ns" recordModule;
            result = lib.evalModules {
              modules = [ wrapped ];
              specialArgs = {
                pkgs = { };
                namespace = "first-ns";
              };
            };
          in
          result.config."second-ns".nsOk;
        expected = true;
      };
    };
  };
}
