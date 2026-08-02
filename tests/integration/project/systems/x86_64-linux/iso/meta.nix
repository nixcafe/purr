{
  inputs,
  lib,
  host,
  name,
  arch,
  archFormat,
  format,
  ...
}:
assert inputs != null;
assert lib != null;
assert host == name;
assert arch == "x86_64";
assert archFormat == "x86_64-linux";
assert format == "linux";
{
  images = [ "iso" ];
  role = "iso-builder";
}
