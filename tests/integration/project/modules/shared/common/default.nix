{
  config,
  lib,
  namespace,
  ...
}:
{
  options.${namespace}.shared = {
    marker = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };
}
