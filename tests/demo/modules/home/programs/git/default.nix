{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  cfg = config.${namespace}.programs.git;
in
{
  options.${namespace}.programs.git = {
    enable = lib.mkEnableOption "git";
  };
  config = lib.mkIf cfg.enable { home.packages = [ pkgs.git ]; };
}
