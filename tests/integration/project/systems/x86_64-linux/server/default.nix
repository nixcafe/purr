{
  config,
  lib,
  namespace,
  purr,
  host,
  system,
  inputs,
  ...
}:
assert lib != null;
assert namespace == "demo";
assert purr != null && purr.name == "server" && purr.arch == "x86_64" && purr.format == "linux";
assert purr.isDarwin == false && purr.isLinux == true;
assert purr.meta.tier == "prod";
assert purr.meta.region == "us-east";
assert purr.meta.images == [ ];
assert purr.meta.deployable == true;
assert host == "server";
assert builtins.isString system;
assert inputs != null;
{
  options.${namespace}.server = {
    answer = lib.mkOption {
      type = lib.types.int;
      default = lib.${namespace}.math.add 40 2;
    };
  };

  config = {
    system.stateVersion = "24.11";
    system.build.toplevel = "toplevel-server";
    networking.hostName = host;
    services.openssh.enable = true;
    environment.systemPackages = [ (lib.${namespace}.strings.upper.upper "abc") ];

    # namespace bridge: forward home-manager config for alice
    purr.users.alice.homeConfig = {
      home.packages = [ "cowsay" ];
    };
  };
}
