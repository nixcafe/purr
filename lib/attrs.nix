_:
let
  optionalAttrs = cond: attrs: if cond then attrs else { };
in
{
  inherit optionalAttrs;
}
