# Directory Structure

All directories are auto-detected under your `src` path:

```
src/
├── lib/                              # Project library (auto-detect: "lib")
│   ├── default.nix                   #   import { lib, inputs, namespace }: returns attrset
│   ├── keys/
│   │   └── default.nix               #   nested → lib.<namespace>.keys
│   └── utils/
│       └── default.nix               #   nested → lib.<namespace>.utils
│                                     #   flattenLib = true → lib.<namespace>
│
├── modules/                          # NixOS/darwin/home modules
│   ├── nixos/                        #   → nixosModules
│   ├── darwin/                       #   → darwinModules
│   ├── home/                         #   → homeModules
│   └── shared/                       #   → merged into nixos + darwin
│
├── packages/                         # Per-system packages (auto-detect: "packages")
│   ├── known-hosts/
│   │   └── default.nix               #   → packages.<system>.known-hosts
│   ├── match-blocks/
│   │   └── default.nix               #   → packages.<system>.match-blocks
│   └── by-name/                      #   Optional by-name convention (packagesByName = true)
│       └── co/
│           └── cowsay/
│               └── package.nix       #   → packages.<system>.cowsay
│
├── legacyPackages/                   # Per-system legacy packages (auto-detect: "legacyPackages")
│   ├── hello/
│   │   └── default.nix               #   → legacyPackages.<system>.hello
│   └── by-name/                      #   Optional by-name convention (legacyPackagesByName = true)
│       └── he/
│           └── hello/
│               └── package.nix       #   → legacyPackages.<system>.hello
│
├── shells/                           # Dev shells (auto-detect: "shells", "devShells")
│   └── default/
│       └── default.nix               #   → devShells.<system>.default
│
├── checks/                           # Per-system checks (auto-detect: "checks")
│   └── pre-commit/
│       └── default.nix               #   → checks.<system>.pre-commit
│
├── overlays/                         # Overlays (auto-detect: "overlays")
│   └── custom/
│       └── default.nix               #   → overlays.custom
│
├── templates/                        # Flake templates (auto-detect: "templates")
│   └── rust/                         #   non-recursive by default
│       └── default.nix               #   → templates.rust
│
├── apps/                             # Per-system apps (auto-detect: "apps")
│   └── serve/
│       └── default.nix               #   → apps.<system>.serve
│
├── formatters/                       # Formatter (auto-detect: "formatters", "formatter")
│   └── default.nix                   #   returns a derivation → formatter.<system>
│                                     #   e.g. { pkgs, ... }: pkgs.nixfmt-rfc-style
│
├── systems/                          # auto-detect: "systems", "hosts"
│   └── x86_64-linux/
│       ├── server/default.nix        # → nixosConfigurations.server
│       └── server/meta.nix           #   optional host meta (see Host Meta)
│                                     #   e.g. { images = ["iso"]; }
│
└── homes/                            # auto-detect: "homes"
    └── x86_64-linux/
        └── alice@server/default.nix  # → homeConfigurations."alice@server"
```

> **hydraJobs:** custom CI jobs live in a top-level `hydraJobs/` directory. Enable with `hydraJobs.enable = true`. See the [hydraJobs](/hydrajobs) page.

## Directory Discovery

Each directory is auto-detected when the option is `null` (default). The discovery order:

| Output | Option | Auto-detect candidates |
|--------|--------|------------------------|
| Library | `libDir` | `lib/` |
| Modules | `modulesDir` | `"modules"` (default) |
| Checks | `checksDir` | `checks/` |
| Shells | `shellsDir` | `shells/` → `devShells/` |
| Overlays | `overlaysDir` | `overlays/` |
| Packages | `packagesDir` | `packages/` |
| Legacy Packages | `legacyPackagesDir` | `legacyPackages/` |
| Apps | `appsDir` | `apps/` |
| Templates | `templatesDir` | `templates/` |
| Formatter | `formatterDir` | `formatters/` → `formatter/` |
| Systems | `systemsDir` | `systems/` → `hosts/` |
| Homes | `homesDir` | `homes/` |

You can override any directory with an explicit name:

```nix
# mkFlake
inputs.purr.lib.mkFlake {
  inherit inputs;
  src = ./.;
  shellsDir = "myshells";
  systemsDir = "hosts";
}

# flake-parts
purr = {
  enable = true;
  src = ./.;
  shellsDir = "myshells";
  systemsDir = "hosts";
};
```
