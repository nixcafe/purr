# Tests for collectModules in lib/modules.nix
# collectModules flattens a nested module attrset into a flat list
# suitable for use in `imports`.
{
  lib,
}:
let
  modulesLib = import ../lib/modules.nix {
    fs = import ../lib/fs.nix;
    inherit lib;
  };
  inherit (modulesLib) collectModules;
in
{
  basic = {
    tests = {
      "flattens a flat attrset of modules" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ];
          };
          b = {
            config.test = 1;
          };
        });
        expected = 2;
      };

      "flattens nested attrs" = {
        expr = builtins.length (collectModules {
          a = {
            b = {
              imports = [ ];
            };
            c = {
              config.test = 1;
            };
          };
        });
        expected = 2;
      };

      "handles empty attrs" = {
        expr = builtins.length (collectModules { });
        expected = 0;
      };

      "treats functions as leaf" = {
        expr = builtins.length (collectModules {
          a = x: x;
        });
        expected = 1;
      };

      "treats paths as leaf" = {
        expr = builtins.length (collectModules {
          a = ./default.nix;
        });
        expected = 1;
      };

      "treats attrsets with imports as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ./a.nix ];
          };
        });
        expected = 1;
      };

      "treats attrsets with options as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            options.services = { };
          };
        });
        expected = 1;
      };

      "treats attrsets with config as leaf" = {
        expr = builtins.length (collectModules {
          a = {
            config.services = { };
          };
        });
        expected = 1;
      };

      "single module at root" = {
        expr = builtins.length (collectModules {
          a = {
            imports = [ ];
          };
        });
        expected = 1;
      };

      "deeply nested 3+ levels" = {
        expr = builtins.length (collectModules {
          a.b.c = {
            imports = [ ];
          };
        });
        expected = 1;
      };

      "mixed types in same tree" = {
        expr = builtins.length (collectModules {
          a = x: x;
          b = ./default.nix;
          c.dir = {
            imports = [ ];
          };
        });
        expected = 3;
      };

      "empty nested attrset is skipped" = {
        expr = builtins.length (collectModules {
          a = { };
          b = {
            imports = [ ];
          };
        });
        expected = 1;
      };
    };
  };
}
