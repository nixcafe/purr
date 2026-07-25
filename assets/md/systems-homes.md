# Systems & Homes

purr auto-discovers NixOS/darwin systems, home-manager homes, and image formats using the `<arch>-<format>/<name>` convention (compatible with [Snowfall Lib](https://snowfall.org)).

## Directory Structure

```
src/
├── systems/                          # auto-detect: "systems", "hosts"
│   ├── x86_64-linux/
│   │   ├── server/default.nix        # → nixosConfigurations.server
│   │   └── laptop/default.nix        # → nixosConfigurations.laptop
│   ├── x86_64-iso/
│   │   └── server/default.nix        # → isoConfigurations.server
│   ├── x86_64-do/
│   │   └── server/default.nix        # → doConfigurations.server
│   └── aarch64-darwin/
│       └── macbook/default.nix       # → darwinConfigurations.macbook
│
├── homes/                            # auto-detect: "homes"
│   ├── x86_64-linux/
│   │   ├── alice@server/default.nix  # → homeConfigurations."alice@server"
│   │   └── bob@server/default.nix    # → homeConfigurations."bob@server"
│   └── aarch64-darwin/
│       └── alice@macbook/default.nix # → homeConfigurations."alice@macbook"
```

## System Output Mapping

| Format in dir name | Flake output key | Builder |
|---|---|---|
| `linux` | `nixosConfigurations.<name>` | `nixosSystem` |
| `darwin` | `darwinConfigurations.<name>` | `darwinSystem` |
| `iso`, `do`, … | `<format>Configurations.<name>` | `nixosSystem` + `image.variant` |

## Home Auto-Linking

Homes named `<user>@<host>` are automatically injected into matching hosts. When `home-manager` (or `homeManager`) is available as an input, building `nixosConfigurations.server` will include all homes with `@server` suffix:

```nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];
  programs.git.enable = true;
}
```

The home is auto-configured via `home-manager.users.alice` in the host's NixOS config. No additional wiring needed.

## Image Formats (nixos-generators replacement)

nixos-generators was merged into nixpkgs (25.05+). Set `image.variant` in the system config to build images. purr auto-detects format directories and adds the variant:

```nix
# systems/x86_64-iso/server/default.nix
{ ... }: {
  image.variant = "iso";  # implied, auto-set by purr
}
```

## Namespace Bridge (system -> home config forwarding)

When a namespace is set (e.g. `namespace = "demo"`), purr defines `options.<ns>.users` and forwards `<ns>.users.<name>.homeConfig` to `home-manager.users.<name>`. This lets you inject home-manager config directly from any NixOS system module:

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, namespace, purr, ... }:
{
  networking.hostName = purr.name;

  ${namespace}.users.alice.homeConfig = {
    home.packages = [ pkgs.cowsay ];
    programs.git.userName = "Alice";
  };
}
```

Keys inside `homeConfig` map directly to home-manager option paths (`home.packages`, `programs.*`, `services.*`, etc.). The bridge provides low-priority defaults — the user's home module (`homes/x86_64-linux/alice@server/default.nix`) always takes priority.

### Priority Order (lowest to highest)

1. `<ns>.users.<name>.homeConfig` (bridge)
2. `home-manager.users.<name>` set directly in any NixOS module
3. The home module file (`homes/.../default.nix`)

## `purr` Metadata

Each system and home module receives a `purr` attrset with metadata about the current configuration. This is passed via `specialArgs` (systems) and `extraSpecialArgs` (homes).

### System Modules (`specialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `name` | `"server"` | System/host name |
| `arch` | `"x86_64"` | Architecture |
| `format` | `"linux"` | linux, darwin, iso, ... |
| `archFormat` | `"x86_64-linux"` | Full arch-format string |
| `isDarwin` | `false` | Whether the target is Darwin |
| `isLinux` | `true` | Whether the target is Linux |
| `homes` | `[{user="alice";host="server";}]` | Linked home configs |

### Home Modules (`extraSpecialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `user` | `"alice"` | Username |
| `host` | `"server"` | Host name |
| `arch` | `"x86_64"` | Architecture |
| `format` | `"linux"` | linux, darwin, ... |
| `archFormat` | `"x86_64-linux"` | Full arch-format string |
| `isDarwin` | `false` | Whether the target is Darwin |
| `isLinux` | `true` | Whether the target is Linux |

> **Note:** The fields above apply to *standalone* homes (discovered from `homes/` but not linked to any system). When a home is auto-linked to a system (via `@host` matching), the home module receives the *system's* `purr` metadata instead.

### Usage Example

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.name;         # "server"
  nixpkgs.hostPlatform = purr.archFormat;  # "x86_64-linux"
}
```

## Auto-Injection

By default (`autoInject = true`), purr auto-injects basic configuration using `lib.mkDefault` — user modules can always override:

| Context | Injected config |
|---|---|
| System config | `networking.hostName = <purr.name>` |
| Home config (linux) | `home.username`, `home.homeDirectory = "/home/<user>"` |
| Home config (darwin) | `home.username`, `home.homeDirectory = "/Users/<user>"` |

Disable with `autoInject = false`.

## Usage in mkFlake

```nix
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  systemsDir = "systems";   # or "hosts", or null to auto-detect
  homesDir = "homes";
}
```

## Usage in flake-parts

```nix
purr = {
  enable = true;
  src = ./.;
  systemsDir = "systems";
  homesDir = "homes";
};
```
