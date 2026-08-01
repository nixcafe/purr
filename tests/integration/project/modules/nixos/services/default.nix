{
  config,
  lib,
  namespace,
  ...
}:
{
  options.${namespace}.services.openssh = {
    enable = lib.mkEnableOption "openssh via ns-aware module";
  };
  config = lib.mkIf config.${namespace}.services.openssh.enable {
    services.openssh.enable = true;
  };
}
