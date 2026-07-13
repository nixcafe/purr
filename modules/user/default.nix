{
  config,
  lib,
  namespace ? null,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.${namespace}.user = {
    name = mkOption {
      type = types.str;
      default = "user";
    };
    home = mkOption {
      type = types.str;
      default = "/home/${config.${namespace}.user.name}";
    };
  };

  config = { };
}
