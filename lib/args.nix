# Shared module-argument construction.
#
# Every purr module call site merges `extraArgs` first and then forces purr's
# own keys (`inputs`, `namespace`, `lib`) on top, so they always win. This is
# the single place that encodes that merge order — per-system / system / home
# call sites add only their site-specific keys.
{
  purrArgs =
    {
      extraArgs,
      inputs,
      namespace,
      lib,
    }:
    extraArgs
    // {
      inherit
        inputs
        namespace
        lib
        ;
    };
}
