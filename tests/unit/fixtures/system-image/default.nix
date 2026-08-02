{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr.meta.images == [ "iso" ];
assert purr.meta.deployable == false;
{
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
