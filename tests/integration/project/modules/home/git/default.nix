{
  config,
  lib,
  namespace,
  ...
}:
{
  options.${namespace}.programs.git = {
    enable = lib.mkEnableOption "git via ns-aware module";
  };
  config = lib.mkIf config.${namespace}.programs.git.enable {
    home.packages = [ "git-pkg" ];
  };
}
