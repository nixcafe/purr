{
  config,
  lib,
  namespace,
  ...
}:
let
  inherit (lib.${namespace}) greet;
  cfg = config.${namespace}.shared.users;
in
{
  options.${namespace}.shared.users = {
    greeting = lib.mkOption {
      type = lib.types.str;
      default = greet "world";
    };
  };
}
