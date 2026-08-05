{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr != null && purr.meta.arch == "x86_64" && purr.meta.format == "linux";
assert purr.meta.images == [ "iso" ];
assert purr.meta.role == "iso-builder";
assert purr.meta.deployable == false;
assert purr.systemMetas.iso.name == "iso";
{
  # image-only host: excluded from nixosConfigurations by default
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
