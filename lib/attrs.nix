{ lib, ... }:
let
  inherit (lib)
    recursiveUpdate
    ;

  mergeShallow = a: b: a // b;
  mergeDeep = recursiveUpdate;
  optionalAttrs = cond: attrs: if cond then attrs else { };
in
{
  inherit
    mergeDeep
    mergeShallow
    optionalAttrs
    ;
}
