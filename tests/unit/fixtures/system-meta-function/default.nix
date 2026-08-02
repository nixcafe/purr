{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr.meta.images == [ "iso" ];
assert purr.meta.tier == "from-function-x86_64";
{
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
