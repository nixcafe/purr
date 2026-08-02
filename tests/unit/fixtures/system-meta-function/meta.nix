{
  inputs,
  lib,
  host,
  name,
  system,
  arch,
  archFormat,
  format,
  ...
}:
assert inputs != null;
assert lib != null;
assert host == name;
assert builtins.isString system;
assert arch == "x86_64";
assert archFormat == "x86_64-linux";
assert format == "linux";
{
  images = [ "iso" ];
  tier = "from-function-${arch}";
}
