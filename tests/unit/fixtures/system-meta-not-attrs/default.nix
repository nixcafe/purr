{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr.meta.images == [ ];
{
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
