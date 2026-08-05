# Systems & Homes

purr auto-discovers NixOS/darwin systems and home-manager homes using the `<arch>-<format>/<name>` convention (compatible with [Snowfall Lib](https://snowfall.org)). Only `linux` and `darwin` formats are supported.

## Directory Structure

```
src/
├── systems/                          # auto-detect: "systems", "hosts"
│   ├── x86_64-linux/
│   │   ├── server/default.nix        # → nixosConfigurations.server
│   │   └── laptop/default.nix        # → nixosConfigurations.laptop
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

## Home Auto-Linking

Homes named `<user>@<host>` are automatically injected into matching hosts. When `home-manager` (or `homeManager`) is available as an input, building `nixosConfigurations.server` will include all homes with `@server` suffix:

```nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];
  programs.git.enable = true;
}
```

The home is auto-configured via `home-manager.users.alice` in the host's NixOS config. No additional wiring needed. For every linked home, purr also:

* sets `home-manager.useGlobalPkgs` and `home-manager.useUserPackages` to `mkDefault true`
* auto-creates `users.users.<name>` (`isNormalUser = mkDefault true`) for non-root users on Linux hosts
* injects the username as a module argument (`_module.args.user = "alice"`) and default `home.username` / `home.homeDirectory`

## Building Images (ISO, qemu, raw, cloud, …)

purr does **not** have special format directories (`x86_64-iso`, `x86_64-do`, …). Instead, nixpkgs (25.05+) already imports `image/images.nix` by default, which makes every NixOS configuration capable of building all image formats out of the box. Just put your system under `systems/<arch>-linux/` and build any image from it:

```bash
# ISO image
nix build .#nixosConfigurations.server.config.system.build.images.iso

# QEMU qcow2 image (EFI)
nix build .#nixosConfigurations.server.config.system.build.images.qemu-efi

# Raw disk image
nix build .#nixosConfigurations.server.config.system.build.images.raw

# DigitalOcean image
nix build .#nixosConfigurations.server.config.system.build.images.digital-ocean

# Amazon EC2 AMI
nix build .#nixosConfigurations.server.config.system.build.images.amazon
```

### Short `images.<host>.<format>` output

Declare which formats to build for a host in its [host meta](/meta) (a `meta.nix` file or `hosts.<name>.meta` config), and purr exposes a top-level `images.<host>.<format>` output. This works regardless of whether [hydraJobs](/hydrajobs) is enabled:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
}
```

```bash
# Short names, always available
nix build .#images.server.iso
nix build .#images.server.qemu
```

Available formats are the same as below. When hydraJobs is enabled, these same declarations are mirrored as `hydraJobs.images.<host>.<format>`.

### Image-only hosts (not deployable)

A host that declares `images` in its meta is treated as an **image-only recipe** by default. It is excluded from `nixosConfigurations`/`darwinConfigurations` (and from the `hydraJobs` config groups), so its `system.build.toplevel` is never evaluated and it cannot be deployed with `nixos-rebuild`. Use this for hosts like installer ISOs that have no root file system and exist only to build images:

```nix
# systems/x86_64-linux/installer/meta.nix
{
  images = [ "iso" ];
}
```

`installer` will **not** show up in `nixosConfigurations`, but `nix build .#images.installer.iso` still works. The image declarations are read cheaply from `meta.nix` — nixpkgs and home-manager are never evaluated just to decide how a host is exposed, and the image derivations stay lazy until you actually build them.

To keep a host deployable **and** build images from it, set `deployable = true`:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
  deployable = true; # stays in nixosConfigurations AND builds images
}
```

> **Note:** `deployable` is a host meta key, not a system option. A host is deployable by default when `images` is empty; declaring `images` without `deployable = true` makes it image-only.

### Available image formats

All formats from the now-deprecated [nixos-generators](https://github.com/nix-community/nixos-generators) are built into nixpkgs:

| Format key | Image type | Format key | Image type |
|---|---|---|---|
| `iso` | Bootable ISO 9660 | `proxmox` | Proxmox VE image |
| `qemu-efi` | QEMU qcow2 (EFI) | `proxmox-lxc` | Proxmox LXC container |
| `qemu` | QEMU qcow2 (BIOS) | `lxc` | LXC container |
| `raw-efi` | Raw disk (EFI) | `lxc-metadata` | LXC metadata tarball |
| `raw` | Raw disk (BIOS) | `oci` | OCI container image |
| `amazon` | AWS EC2 AMI | `vagrant-virtualbox` | Vagrant VirtualBox |
| `azure` | Azure VM image | `virtualbox` | VirtualBox OVA |
| `google-compute` | GCP image | `vmware` | VMware VMDK |
| `digital-ocean` | DigitalOcean image | `kubevirt` | KubeVirt container disk |
| `hyperv` | Hyper-V VHDX | `cloudstack` | Apache CloudStack |
| `linode` | Linode image | `openstack` | OpenStack image |
| `kexec` | Netboot kexec image | `sd-card` | Raspberry Pi / SD card |

### If you need different configs for different images

Put multiple systems under `systems/x86_64-linux/` with different names. A minimal installer config is a good candidate for an image-only host (see [Image-only hosts](#image-only-hosts-not-deployable)):

```
systems/x86_64-linux/
  ├── production/default.nix   # full server
  └── installer/default.nix    # minimal ISO config
```

```nix
# systems/x86_64-linux/installer/meta.nix
{
  images = [ "iso" ];
}
```

Then build:

```bash
nix build .#images.installer.iso
```

## Namespace Bridge (system -> home config forwarding)

On any host with linked homes (when home-manager is available as an input), purr defines the option `purr.users`. Setting `purr.users.<name>.homeConfig` from any NixOS module forwards that config to `home-manager.users.<name>`. This works whether or not a `namespace` is set:

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.meta.name;

  purr.users.alice.homeConfig = {
    home.packages = [ pkgs.cowsay ];
    programs.git.userName = "Alice";
  };
}
```

Keys inside `homeConfig` map directly to home-manager option paths (`home.packages`, `programs.*`, `services.*`, etc.). The bridge provides low-priority defaults — the user's home module (`homes/x86_64-linux/alice@server/default.nix`) always takes priority.

### Priority Order (lowest to highest)

1. `purr.users.<name>.homeConfig` (bridge)
2. `home-manager.users.<name>` set directly in any NixOS module
3. The home module file (`homes/.../default.nix`)

## `purr` Metadata

Each system and home module receives a `purr` attrset with metadata about the current configuration. This is passed via `specialArgs` (systems) and `extraSpecialArgs` (homes).

### System Modules (`specialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `meta` | see [Host Meta](/meta) | Merged host metadata (contains `name`, `arch`, `format`, `isDarwin`, `isLinux`, `system`, `homes`, `images`, `deployable`, plus custom keys) |
| `systemMetas` | `{ server = {...}; workstation = {...}; }` | Registry of **every** discovered host's merged meta, keyed by host name (including self) |

### Home Modules (`extraSpecialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `meta` | `{ user = "alice"; host = "server"; ... }` | Home metadata: `user`, `host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system` |
| `systemMeta` | see [Host Meta](/meta) | Merged meta of the system named by the home's host, or `null` when no matching system exists |
| `systemMetas` | `{ server = {...}; ... }` | The same global host registry as systems receive |
| `lib` | `{ hm = {...}; ... }` | The merged namespace lib (with home-manager's `lib.hm` extension), also available as `lib` for standalone homes |

> **Note:** `purr.lib` is the merged namespace lib, available uniformly in **both** standalone and bridged homes — use `purr.lib.<namespace>.xxx` from any home module. Standalone homes additionally receive the same lib under `lib`.

### Usage Example

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.meta.name;       # "server"
  nixpkgs.hostPlatform = purr.meta.archFormat;  # "x86_64-linux"
  services.foo.enable = purr.meta.tier == "prod";  # custom meta key
  services.bar.enable = purr.systemMetas.workstation.tier == "dev";
}
```

````nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, lib, purr, ... }:
{
  home.packages = [ pkgs.neovim ];
  # systemMeta is the meta of "server" (or null when not linked to a system)
  programs.git.enable = purr.systemMeta != null;
}

## Auto-Injection

By default (`autoInject = true`), purr auto-injects basic configuration using `lib.mkDefault` — user modules can always override:

| Context | Injected config |
|---|---|
| System config | `networking.hostName = <purr.meta.name>` |
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
````

## Usage in flake-parts

```nix
purr = {
  enable = true;
  src = ./.;
  systemsDir = "systems";
  homesDir = "homes";
};
```
