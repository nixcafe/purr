{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  cfg = config.${namespace}.services.openssh;
in
{
  options.${namespace}.services.openssh = {
    enable = lib.mkEnableOption "SSH service via ns-aware module";
  };
  config = lib.mkIf cfg.enable { services.openssh.enable = true; };
}
