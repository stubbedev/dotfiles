# STUBBEDEV DOTFILES

Personal Linux dotfiles and utilities, bundled as a Nix flake with an
installer and a maintenance front-end. Works on both NixOS and non-NixOS
hosts via home-manager.

## STRUCTURE

The config is kept self-contained: the repo is symlinked to `~/.stubbe`, so
removing the repo removes the settings with it.

```tree
.stubbe/
├── flake.nix        # dendritic flake-parts entrypoint (inputs + import-tree)
├── lib.nix          # aggregates lib/ into the homeLib.* API
├── lib/             # shared helpers, one domain per file (functions only)
├── constants.nix    # path + theme constants
├── modules/         # dendritic modules (auto-loaded via import-tree)
│   ├── hosts/       # standalone home-manager configurations
│   ├── nixos/       # NixOS system modules + nixos/hosts/ definitions
│   ├── packages/    # HM package bundles (feature-gated installs)
│   ├── programs/    # HM program configuration (settings, not just pkgs)
│   ├── home/        # HM session/base config (xdg/, zsh/, systemd, scripts)
│   ├── files/       # HM dotfile content (mail, gh, vpn, ...)
│   ├── theme/       # HM gtk/qt/dconf theming
│   ├── activation/  # HM activations (privileged/ = sudo-prompted setups)
│   ├── checks/      # flake checks (lint/eval/config sanity)
│   └── installer/   # installer ISO configuration
├── bin/             # shell scripts built into Nix-managed binaries
├── src/             # per-application configs (hypr, niri, wayle, zsh, ...)
└── README.md
```

`bin/` scripts are built into `~/.nix-profile/bin/` via home-manager.
`stb-install` is the only one that runs from the checkout — it bootstraps
Nix and home-manager on a fresh host.

## CONVENTIONS

The patterns every module follows (keep new code consistent with these):

1. **Registration.** Every reusable module registers under
   `flake.modules.homeManager.<name>` or `flake.modules.nixos.<name>`,
   where `<name>` is the camelCase of its path under `modules/`, minus a
   leading directory that duplicates the bag (`theme/gtk.nix` →
   `themeGtk`, `packages/cli/core.nix` → `packagesCliCore`,
   `nixos/fonts.nix` → `fonts`, `home/zsh/zsh.nix` → `homeZsh`). Hosts
   import whole bags via `builtins.attrValues`; nothing references
   modules by name in code.
2. **No opt-outs.** Every file under `modules/` is auto-loaded by
   import-tree and must be a flake-part; there are no underscore-prefixed
   exceptions. Pure Nix functions that several modules share (e.g.
   `lib/zsh-packages.nix`, `lib/chrome-policy.nix`) live under `lib/`
   instead, where nothing is auto-loaded.
3. **lib/ vs modules/.** `lib/*.nix` files are pure function namespaces,
   each taking its dependencies as explicit arguments; they never touch
   module-system state. Anything pkgs-dependent guards lazily so NixOS
   callers can import without pkgs. `lib.nix` re-exports everything flat
   as the `homeLib.*` API consumed inside HM modules.
4. **Feature gates & platform split.** Behaviour toggles live in
   `features.*` options (modules/features.nix) and gate content with
   `lib.mkIf config.features.<x>`. NixOS owns system files
   (`modules/nixos/`); identical concerns on non-NixOS hosts are handled
   by privileged activation snippets that self-gate on
   `config.host.platform != "nixos"`.
5. **Dual-platform modules.** When one concern needs both an HM and a
   NixOS module (e.g. ollama), a single file under `modules/packages/`
   may register into BOTH bags with the same derived name — shared
   declarations go in the file's top-level `let`.
6. **Activations.** Files in `modules/activation/{non-privileged,
   privileged}/` register like any other module but delegate the DAG/
   sudo scaffolding to `lib/activation-setups.nix`
   (`mkSetupModule` / `mkSudoSetupModule`), passing their metadata —
   `{ enableIf ?, args }` plus an explicit `name` — through unchanged.
   The key equals the camelCase of the file stem (`setup-greetd.nix` →
   `setupGreetd`), which doubles as the `home.activation.*` node name.

## INSTALLATION

```sh
git clone --depth 1 https://github.com/stubbedev/dotfiles.git
cd dotfiles && ./bin/stb-install
```

The installer prompts for what to install. Day-to-day rebuilds then run
through `hm`.

## APPLYING THE CONFIG

The flake lives at the repo root. Apply with:

```sh
hm switch --flake "path:$HOME/.stubbe"
```

Or directly with home-manager:

```sh
home-manager switch --flake .#stubbe --impure
```

`--impure` is required because activation scripts read `$HOME` and detect
the host distribution at evaluation time.

## NIXOS INSTALLER ISO

Build a bootable installer ISO that mirrors the `stubbe-nixos` host:

```sh
nix build .#installer-iso --impure
# Output: ./result/iso/*.iso — flash to a USB stick.
```

Boot the live USB on the target, log in as `root`, and run:

```sh
stb-install-nixos
```

It partitions the disks as a btrfs volume, runs `nixos-install`, and clones
the repo to `/mnt/etc/nixos`.

Optional hardening is available behind per-host flags in the host file
(`modules/nixos/hosts/stubbe-nixos.nix`):

- **Secure Boot** (`host.secureBoot`) — lanzaboote signed bootloader; enroll
  keys with `sbctl` first.
- **Impermanence** (`host.impermanent`) — wipes `/` on every boot, keeping
  only paths declared in `modules/nixos/impermanence.nix`.

Both require setup steps before flipping the flag — see the comments in the
host file and module.

![Wallpaper preview](./src/wallpapers/traffic.png)
