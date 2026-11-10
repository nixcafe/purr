# Directory Structure

purr resolves each directory under the project `src` path. Most directories are
optional; a directory is used when it exists.

```
src/
├── lib/                              # Project library (auto-detect: "lib")
│   ├── default.nix                   #   { lib, inputs, namespace }: returns an attrset
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
│   │                                 #   also registered into pkgs.<name> (packagesToPkgs)
│   ├── known-hosts/
│   │   └── default.nix               #   → packages.<system>.known-hosts, pkgs.known-hosts
│   ├── match-blocks/
│   │   └── default.nix               #   → packages.<system>.match-blocks, pkgs.match-blocks
│   └── by-name/                      #   Optional by-name layout (packagesByName = true)
│       └── co/
│           └── cowsay/
│               └── package.nix       #   → packages.<system>.cowsay, pkgs.cowsay
│
├── legacyPackages/                   # Per-system legacy packages (auto-detect: "legacyPackages")
│   ├── hello/
│   │   └── default.nix               #   → legacyPackages.<system>.hello
│   └── by-name/                      #   Optional by-name layout (legacyPackagesByName = true)
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
├── hydraJobs/                        # Custom CI jobs (used when hydraJobs.enable = true)
│   └── build/
│       └── hello/
│           └── default.nix           #   → hydraJobs.build.<system>.hello
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

Packages under `packages/` are also registered in `pkgs` as `pkgs.<name>`, so any
per-system module can use them. Disable this with `packagesToPkgs = false`. See
[Packages](/mkflake#packages).

Custom CI jobs live in `hydraJobs/` and are used when `hydraJobs.enable = true`. See
the [hydraJobs](/hydrajobs) page.

## Directory discovery

Each optional directory is resolved from the option value or from the candidate list
when the option is `null`. `modulesDir` is a name with the default `"modules"`, not an
auto-detected path.

| Output | Option | Auto-detect candidates |
|--------|--------|------------------------|
| Library | `libDir` | `lib/` |
| Modules | `modulesDir` | `"modules"` (default) |
| Checks | `checksDir` | `checks/` |
| Shells | `shellsDir` | `shells/` → `devShells/` |
| Overlays | `overlaysDir` | `overlays/` |
| Packages | `packagesDir` | `packages/` |
| Legacy packages | `legacyPackagesDir` | `legacyPackages/` |
| Apps | `appsDir` | `apps/` |
| Templates | `templatesDir` | `templates/` |
| Formatter | `formatterDir` | `formatters/` → `formatter/` |
| Systems | `systemsDir` | `systems/` → `hosts/` |
| Homes | `homesDir` | `homes/` |
| Hydra jobs | `hydraJobs.dir` | `hydraJobs/` |

Override any directory with an explicit name:

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
