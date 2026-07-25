# flake-parts Integration

purr works as a [flake-parts](https://github.com/hercules-ci/flake-parts) module, giving you access to all purr features alongside other flake-parts modules.

## Setup

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purr.url = "github:nixcafe/purr";
    my-extra-modules.url = "github:user/my-extra-modules";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.purr.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      purr = {
        enable = true;
        src = ./.;
        namespace = "cattery";
        extraModules.nixos = [
          inputs.my-extra-modules.nixosModules.default
        ];
      };
    };
}
```

## Options

All options are under the `purr.*` namespace.

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.enable` | bool | `false` | Enable purr |
| `purr.src` | path | *required* | Project root directory |
| `purr.namespace` | nullOr str | `null` | Module option namespace |
| `purr.libDir` | nullOr str | `null` | auto-detects `lib/` |
| `purr.flattenLib` | bool | `false` | Flatten lib subdirectories into root |
| `purr.modulesDir` | str | `"modules"` | Module directory name under src |
| `purr.moduleTypes` | attrs | See below | Subdirectory mapping per output |
| `purr.extraModules` | attrs | `{}` | `{ nixos = [...]; darwin = [...]; home = [...]; }` |
| `purr.bundleModules` | bool | `false` | Bundle all modules into a `default` module |
| `purr.bundleExtraModules` | bool | `true` | Include extra modules in the `default` bundle |

Default `moduleTypes`:

```nix
{
  nixos = ["nixos" "shared"];
  darwin = ["darwin" "shared"];
  home = ["home"];
}
```

### Directory Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.checksDir` | nullOr str | `null` | auto-detects `checks/` |
| `purr.shellsDir` | nullOr str | `null` | auto-detects `shells/` then `devShells/` |
| `purr.overlaysDir` | nullOr str | `null` | auto-detects `overlays/` |
| `purr.packagesDir` | nullOr str | `null` | auto-detects `packages/` |
| `purr.appsDir` | nullOr str | `null` | auto-detects `apps/` |
| `purr.templatesDir` | nullOr str | `null` | auto-detects `templates/` |
| `purr.templatesRecursive` | bool | `false` | Whether to scan `templates/` recursively |
| `purr.systemsDir` | nullOr str | `null` | auto-detects `systems/` then `hosts/` |
| `purr.homesDir` | nullOr str | `null` | auto-detects `homes/` |

### Other Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `purr.nixpkgsConfig` | attrs | `{}` | nixpkgs config (`allowUnfree`, etc.) |
| `purr.autoInject` | bool | `true` | Auto-inject `networking.hostName`, `home.username`, etc. |

## Custom Module Directories

You can customize which subdirectories are scanned for each module type:

```nix
purr.moduleTypes = {
  nixos = ["nixos" "shared" "container" "nixos-musl"];
};
```

## Extra Modules from Other Flakes

Inject external modules alongside auto-discovered ones:

```nix
purr.extraModules = {
  nixos = [
    inputs.cattery-modules.nixosModules.default
    inputs.disko.nixosModules.default
  ];
};
```

## Default Module Bundle

By default, sub-modules are exported individually. Enable `bundleModules = true` to auto-generate a `default` module that imports all sub-modules:

```nix
purr.bundleModules = true;
```

Users can then import with:

```nix
{ imports = [ inputs.myflake.nixosModules.default ]; }
```

Set `bundleExtraModules = false` to exclude extraModules from the default bundle (only auto-discovered modules will be included). If you define your own `default` module under `modules/`, the auto-generated bundle is skipped.
