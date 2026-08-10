# Effective-input resolution for per-host role overrides.
#
# Roles (`nixpkgs`, `home-manager`, `nix-darwin`) map each host to one of
# purr's *effective* inputs — the result of the flake's `inputsFor`
# transform (filtering/replacing the raw flake inputs before purr consumes
# them internally). A host's merged meta may pin a role to a specific
# effective-input key via `meta.roles.<role>`; otherwise the role falls back
# to its conventional key (`nixpkgs`, `home-manager`, ...).
#
# Module arguments are never affected: modules always receive the raw flake
# inputs. This resolution only drives how purr itself builds pkgs, system
# configs, and home configs.
{
  # Resolve the effective input for a role on a host.
  #
  #   effectiveInputs : the post-`inputsFor` inputs (internal only)
  #   key             : the effective-input key to use (a string)
  #   context         : e.g. `"host 'server'"` — used in error messages
  #
  # Throws a clear error when the key is not a string or not present in the
  # effective inputs.
  resolveRole =
    {
      effectiveInputs,
      key,
      context,
    }:
    if !builtins.isString key then
      throw "purr: ${context}: role input name must be a string, got '${builtins.typeOf key}'"
    else
      effectiveInputs.${key}
        or (throw "purr: ${context}: role input '${key}' is not a key of the effective inputs (the inputsFor result). Keep the input in inputsFor if hosts need to reference it.");

  # Conventional effective-input key for the home-manager role, auto-detected
  # from the two common input names. Returns null when neither is present.
  defaultHomeManager =
    effectiveInputs:
    if effectiveInputs ? home-manager then
      "home-manager"
    else if effectiveInputs ? homeManager then
      "homeManager"
    else
      null;

  # Same for the nix-darwin role.
  defaultNixDarwin =
    effectiveInputs:
    if effectiveInputs ? nix-darwin then
      "nix-darwin"
    else if effectiveInputs ? darwin then
      "darwin"
    else
      null;
}
