{
  config,
  lib,
  namespace,
  ...
}:
{
  options.${namespace}.base = {
    greeting = lib.mkOption {
      type = lib.types.str;
      default = lib.${namespace}.strings.upper.upper "hi";
    };
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf config.${namespace}.base.enabled {
    environment.systemPackages = [ "base-pkg" ];
  };
}
