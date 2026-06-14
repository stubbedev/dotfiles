# STUBBEDEV DOTFILES

Personal Linux dotfiles and utilities, bundled as a Nix flake with an
installer and a maintenance front-end. Works on both NixOS and non-NixOS
hosts via home-manager.

## STRUCTURE

The config is kept self-contained: the repo is symlinked to `~/.stubbe`, so
removing the repo removes the settings with it.

```tree
.stubbe/
├── flake.nix        # dendritic flake-parts entrypoint
├── lib.nix lib/     # shared lib helpers
├── constants.nix    # path + theme constants
├── modules/         # dendritic modules (auto-loaded via import-tree)
├── bin/             # shell scripts built into Nix-managed binaries
├── src/             # per-application configs (hypr, niri, wayle, zsh, ...)
└── README.md
```

`bin/` scripts are built into `~/.nix-profile/bin/` via home-manager.
`stb-install` is the only one that runs from the checkout — it bootstraps
Nix and home-manager on a fresh host.

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
