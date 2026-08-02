{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr.meta.name == "myhost";
assert purr.meta.arch == "x86_64";
assert purr.meta.system == "x86_64-linux";
assert purr.meta.images == [ "iso" ];
{
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
