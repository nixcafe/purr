{
  lib,
  purr,
  ...
}:
assert lib != null;
assert purr.meta.labels.env == "prod";
assert purr.meta.labels.team == "core";
assert purr.meta.labels.extra == true;
{
  system.stateVersion = "24.11";
  system.build.images.iso = "iso-drv";
}
