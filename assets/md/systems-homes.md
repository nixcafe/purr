# Systems & Homes

purr discovers NixOS and darwin systems from `<arch>-<format>/<name>` and
home-manager homes from `<arch>-<format>/<user>@<host>`. Only the `linux` and `darwin`
formats are supported.

## Directory layout

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

## Output mapping

| Format in directory name | Flake output key | Builder |
|---|---|---|
| `linux` | `nixosConfigurations.<name>` | `nixosSystem` |
| `darwin` | `darwinConfigurations.<name>` | `darwinSystem` |

## Home auto-linking

Homes named `<user>@<host>` are linked to the matching system. When `home-manager`
(or `homeManager`) is available as an input, building `nixosConfigurations.server`
includes every home with the `@server` suffix:

```nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.neovim ];
  programs.git.enable = true;
}
```

The home is added through `home-manager.users.alice` in the host's NixOS
configuration. For every linked home, purr also:

* sets `home-manager.useGlobalPkgs` and `home-manager.useUserPackages` to
  `mkDefault true`
* creates `users.users.<name>` (`isNormalUser = mkDefault true`) for non-root users on
  Linux hosts
* passes the username as `_module.args.user` and injects `home.username` and
  `home.homeDirectory` as defaults

## Building images

purr does not use special format directories such as `x86_64-iso`. nixpkgs 25.05 and
later imports `image/images.nix` by default, so every NixOS configuration exposes
`system.build.images`. Put the system under `systems/<arch>-linux/` and build an image
from it:

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

Declare the formats for a Linux host in its [host meta](/meta), either in `meta.nix`
or in `hosts.<name>.meta`. purr then exposes a top-level
`images.<host>.<format>` output:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
}
```

```bash
nix build .#images.server.iso
nix build .#images.server.qemu
```

This output exists whether or not hydraJobs is enabled. When `hydraJobs.systems` is
set, it also filters the `images` output. When hydraJobs is enabled, the same
declarations are mirrored as `hydraJobs.images.<host>.<format>`.

### Image-only hosts

On Linux, a host that declares `images` in its meta is an image-only recipe by default.
It is excluded from `nixosConfigurations` and `darwinConfigurations`, and from the
hydraJobs config groups. Its `system.build.toplevel` is never evaluated, so it cannot
be deployed with `nixos-rebuild`. Use this for hosts such as installer ISOs that have
no root file system:

```nix
# systems/x86_64-linux/installer/meta.nix
{
  images = [ "iso" ];
}
```

`installer` does not appear in `nixosConfigurations`, but
`nix build .#images.installer.iso` works. Meta is read from `meta.nix` before nixpkgs
or home-manager is evaluated, and the image derivations stay lazy.

To keep a host deployable and build images from it, set `deployable = true`:

```nix
# systems/x86_64-linux/server/meta.nix
{
  images = [ "iso" "qemu" ];
  deployable = true;
}
```

`deployable` is a host meta key, not a system option. A host is deployable by default
when `images` is empty, or when the host is darwin. On Linux, declaring `images`
without `deployable = true` makes the host image-only.

### Available image formats

These formats come from nixpkgs `image/images.nix`:

| Format key | Image type | Format key | Image type |
|---|---|---|---|
| `iso` | Bootable ISO 9660 | `proxmox` | Proxmox VE image |
| `iso-installer` | Installer ISO | `proxmox-lxc` | Proxmox LXC container |
| `qemu-efi` | QEMU qcow2 (EFI) | `lxc` | LXC container |
| `qemu` | QEMU qcow2 (BIOS) | `lxc-metadata` | LXC metadata tarball |
| `raw-efi` | Raw disk (EFI) | `oci` | OCI container image |
| `raw` | Raw disk (BIOS) | `vagrant-virtualbox` | Vagrant VirtualBox |
| `amazon` | AWS EC2 AMI | `virtualbox` | VirtualBox OVA |
| `azure` | Azure VM image | `vmware` | VMware VMDK |
| `google-compute` | GCP image | `kubevirt` | KubeVirt container disk |
| `digital-ocean` | DigitalOcean image | `cloudstack` | Apache CloudStack |
| `hyperv` | Hyper-V VHDX | `openstack` | OpenStack image |
| `linode` | Linode image | `openstack-zfs` | OpenStack image with ZFS |
| `kexec` | Netboot kexec image | `sd-card` | Raspberry Pi / SD card |

### Different configs for different images

Put multiple systems under `systems/x86_64-linux/` with different names. A minimal
installer config is a good candidate for an image-only host:

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

## Namespace bridge (system to home config)

On a host with linked homes, purr defines the option `purr.users`. Setting
`purr.users.<name>.homeConfig` from any NixOS module forwards that config to
`home-manager.users.<name>`. The option exists whether or not a `namespace` is set:

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

Keys inside `homeConfig` map directly to home-manager option paths
(`home.packages`, `programs.*`, `services.*`, and so on). The bridge config is
forwarded as a normal-priority home-manager module. If both the bridge and the home
module set the same non-mergeable option at normal priority, the module system reports
a conflict. Use `lib.mkDefault` on one side when the home module should be able to
override a bridge value.

The bridge is added before the home module in the import list. Import order does not
change option priority.

## `purr` metadata

Each system and home module receives a `purr` attrset with metadata about the current
configuration. It is passed through `specialArgs` for systems and `extraSpecialArgs`
for homes.

### System modules (`specialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `meta` | see [Host Meta](/meta) | Merged host metadata: `name`, `host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system`, `homes`, `images`, `deployable`, `roles`, plus custom keys |
| `systemMetas` | `{ server = {...}; workstation = {...}; }` | Registry of every discovered host's merged meta, keyed by host name, including the current host |

### Home modules (`extraSpecialArgs.purr`)

| Field | Example | Description |
|---|---|---|
| `meta` | `{ user = "alice"; host = "server"; ... }` | Standalone homes: home metadata (`user`, `host`, `arch`, `archFormat`, `format`, `isDarwin`, `isLinux`, `system`). Bridged homes: the host's merged meta, as described in [Host Meta](/meta) |
| `systemMeta` | see [Host Meta](/meta) | Merged meta of the system named by the home's host, or `null` when no matching system exists. In a bridged home this is the same host meta passed as `meta` |
| `systemMetas` | `{ server = {...}; ... }` | The same host registry that systems receive |
| `lib` | `{ hm = {...}; ... }` | The merged namespace lib with home-manager's `lib.hm` extension, also available as `lib` for standalone homes |

Bridged homes receive the host's merged meta as `purr.meta`, so `purr.meta.user` is
not set there. Use the `user` module argument in home modules that run both
standalone and bridged.

`purr.lib` is the merged namespace lib with `lib.hm` re-added. It is available in
both standalone and bridged homes, so `purr.lib.<namespace>.xxx` works from any home
module. Bridged homes keep home-manager's own evaluation lib and do not receive a
`lib` override. Standalone homes also receive their evaluation lib as `lib`;
`purr.lib` follows the home's resolved nixpkgs role.

### Usage

```nix
# systems/x86_64-linux/server/default.nix
{ config, pkgs, lib, purr, ... }:
{
  networking.hostName = purr.meta.name;              # "server"
  nixpkgs.hostPlatform = purr.meta.archFormat;       # "x86_64-linux"
  services.foo.enable = purr.meta.tier == "prod";    # custom meta key
  services.bar.enable = purr.systemMetas.workstation.tier == "dev";
}
```

```nix
# homes/x86_64-linux/alice@server/default.nix
{ pkgs, lib, purr, ... }:
{
  home.packages = [ pkgs.neovim ];
  # systemMeta is the meta of "server", or null when not linked to a system
  programs.git.enable = purr.systemMeta != null;
}
```

## Auto-injection

By default (`autoInject = true`), purr injects basic configuration with
`lib.mkDefault`, so user modules can override it:

| Context | Injected config |
|---|---|
| System config | `networking.hostName = <purr.meta.name>` |
| Home config (linux) | `home.username`, `home.homeDirectory = "/home/<user>"` |
| Home config (darwin) | `home.username`, `home.homeDirectory = "/Users/<user>"` |

Disable the defaults with `autoInject = false`.

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
