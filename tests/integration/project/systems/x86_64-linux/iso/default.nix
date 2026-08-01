{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr != null && purr.arch == "x86_64" && purr.format == "linux";
{
  # image-only host: excluded from nixosConfigurations by default
  purr.images = [ "iso" ];
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
