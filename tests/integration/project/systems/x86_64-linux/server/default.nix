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
assert
  purr != null
  && purr.meta.name == "server"
  && purr.meta.arch == "x86_64"
  && purr.meta.format == "linux";
assert purr.meta.isDarwin == false && purr.meta.isLinux == true;
assert purr.meta.tier == "prod";
assert purr.meta.region == "us-east";
assert purr.meta.images == [ ];
assert purr.meta.deployable == true;
assert purr.systemMetas.server.name == "server";
assert purr.systemMetas.macbook.name == "macbook";
assert purr.systemMetas.iso.name == "iso";
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

    # host-level nixpkgs overrides at default priority must MERGE with purr's
    # injected defaults (not silently replace them)
    nixpkgs.overlays = [ "server-extra-overlay" ];
    nixpkgs.config = {
      permittedInsecurePackages = [ "host-extra" ];
    };

    # namespace bridge: forward home-manager config for alice
    purr.users.alice.homeConfig = {
      home.packages = [ "cowsay" ];
    };
  };
}
