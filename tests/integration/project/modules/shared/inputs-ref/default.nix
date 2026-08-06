{
  config,
  lib,
  inputs,
  namespace,
  ...
}:
{
  options.${namespace}.inputsRef = {
    hasDefiningInputs = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = {
    environment.systemPackages = [ "inputs-ref-pkg" ];
    ${namespace}.inputsRef.hasDefiningInputs = inputs ? home-manager;
  };
}
