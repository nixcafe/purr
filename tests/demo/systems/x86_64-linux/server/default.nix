{
  config,
  pkgs,
  lib,
  namespace,
  purr,
  inputs,
  host,
  system,
  ...
}:
assert purr != null;
assert builtins.isString host;
assert lib != null;
{
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.efiSupport = true;
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  networking.hostName = host;
  system.stateVersion = "24.11";
  services.openssh.enable = true;
  environment.systemPackages = [ pkgs.hello ];

  environment.etc."purr-test-system".text = ''
    namespace=${namespace}
    hostname=${host}
    arch=${purr.arch}
    format=${purr.format}
    libHasNamespace=${toString (lib ? "demo")}
    greeting=${lib.demo.greet "nixos"}
  '';

  # namespace bridge: inject home-manager config from system module
  purr.users.alice.homeConfig = {
    home.packages = [ pkgs.cowsay ];
    home.file = {
      "from-system-bridge".text = "injected via namespace bridge from system module";
    };
  };
}
