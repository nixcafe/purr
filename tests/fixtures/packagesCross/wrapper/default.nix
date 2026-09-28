# Resolves `base` from the surrounding pkgs fixpoint (auto-registration).
{ base, ... }: {
  _type = "wrapper";
  wrapped = base._type;
}
