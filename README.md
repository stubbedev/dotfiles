# STUBBEDEV DOTFILES

Personal Linux dotfiles and utilities, bundled as a Nix flake with an
installer and a maintenance front-end. Works on both NixOS and non-NixOS
hosts via home-manager.

## STRUCTURE

The config is kept self-contained: the repo is symlinked to `~/.stubbe`, so
removing the repo removes the settings with it.

One file per **aspect**, and each aspect owns everything about itself — its
packages, its config files, its systemd units, its activation steps, and both
its NixOS and its home-manager half. There is no `packages/` bag, no `files/`
bag and no `activation/` bag to keep in sync: to change how mail works you edit
`modules/mail.nix`, and that is the whole story.

```tree
.stubbe/
├── flake.nix              # inputs; outputs are `import-tree ./modules`
├── modules/
│   ├── core/              # the foundation (see CONVENTIONS below)
│   ├── hosts/             # host definitions, one file each
│   ├── dev/               # flake checks, lint, `nix fmt`
│   ├── scripts/           # the `hm` front-end, launchers, clip, ISO burner
│   ├── ai/, browsers/     # aspects big enough to want a directory
│   └── <aspect>.nix       # mail, shell, hyprland, lys-shell, power, storage, …
├── bin/                   # ONLY the pre-Nix bootstraps (stb-install*)
├── src/                   # the few real files: nvim + hyprland live-edit
│                          # trees, aerc stylesets, wallpapers
├── certs/                 # the srv root CA (public cert); seeded into the
│                          # system trust store at build time
└── secrets/               # sops-encrypted, keyed per machine in .sops.yaml
```

Every config file and script is inline Nix inside its aspect module. Scripts
become PATH bins through `pkgs.stubbe.bashApp` (build-time shellcheck),
`pkgs.stubbe.zshApp` (build-time `zsh -n`), or `pkgs.stubbe.shellScript` /
`shellScriptBin` for scripts that must keep plain (non-`set -euo pipefail`)
semantics. `bin/stb-install` runs from the checkout — it bootstraps Nix and
home-manager on a fresh host.

## CONVENTIONS

1. **One file, one aspect, both classes.** Every file under `modules/`
   registers under `flake.modules.homeManager.<aspect>` and/or
   `flake.modules.nixos.<aspect>`. Values shared between the two halves are
   let-bound at the top of the file, which is what stops a NixOS module and its
   non-NixOS activation from drifting apart. Hosts import a whole class with
   `builtins.attrValues`; nothing references a module by name.

2. **No opt-outs.** Every `.nix` file under `modules/` is auto-loaded by
   import-tree and must be a flake-parts module. There are no
   underscore-prefixed exceptions.

3. **Three layers of shared code, and no fourth.**
   - `stubbe.lib.*` (`modules/core/lib/`) — pure data and pure functions:
     `colors`, `theme`, `newtabUrl`, `cache`, the `hm` command catalogue,
     `managedBy`. Needs nothing; mirrored as `flake.lib`.
   - `pkgs.stubbe.*` (`modules/core/pkgs/`) — every builder that needs `pkgs`:
     `file`, `secret`, `bashApp`, `zshApp`, `shellScript`, `gen`, `gl`,
     `check`, and the `setup.*` script fragments. Re-exports all of
     `stubbe.lib`, and is reachable from any module of any class because it
     rides on `pkgs`.
   - `config.stubbe.*` — options for anything derived from the evaluated
     configuration: `paths`, `gfx`, `setup`, `mutable`, `userFeatures`.

   There is no `specialArgs` and no `extraSpecialArgs` anywhere. A module that
   needs a flake input resolves it at flake-parts level, where `inputs` is
   already in scope. This is what makes every aspect movable between the two
   targets without rewiring.

4. **Feature gates and the platform split.** Behaviour toggles are
   `features.*` options (`modules/core/features.nix`), gated with
   `lib.mkIf config.features.<x>`. NixOS aspects gate on
   `config.stubbe.userFeatures.<x>`, the same flags resolved once from the
   primary user. On NixOS the declarative half owns system state; on any other
   distro the same aspect's `stubbe.setup.<name>.privileged` activation writes
   the equivalent files into `/etc`, and gates itself off on NixOS.

5. **Activation steps.** `stubbe.setup.<name>` (`modules/core/setup.nix`) is
   the one way to run imperative work at switch time. The attribute name is the
   DAG node name; `privileged = true` adds the shared sudo-prompt scaffolding,
   a content-hash lock so an unchanged step costs nothing, and the NixOS gate.

6. **Mutable files.** `xdg.configFile` / `home.file` — read-only store symlinks
   — are the default. `stubbe.mutable.<path>` (`modules/core/mutable.nix`) is
   for the two cases that cannot be: `link` (point at the live checkout so an
   edit needs no rebuild) and `copy` (the app rewrites the file, so re-assert
   ours each switch).

7. **Everything is Nix.** Config is structured Nix data rendered through
   `lib.generators` / `pkgs.formats` where a format exists (INI, TOML, YAML,
   JSON), and inline strings where none does — so the Catppuccin palette
   exists once, in `modules/core/lib/palette.nix`, and flows into every themed
   surface by interpolation. The only real files left under `src/` are the
   ones that must be files: the nvim and hyprland live-edit trees
   (`stubbe.mutable` link), binary wallpapers, and the sops secrets.

## INSTALLATION

```sh
git clone --depth 1 https://github.com/stubbedev/dotfiles.git
cd dotfiles && ./bin/stb-install
```

The installer asks once for confirmation, then does everything. Day-to-day rebuilds then run
through `hm`.

## APPLYING THE CONFIG

The flake lives at the repo root. Apply with:

```sh
hm switch --flake "path:$HOME/.stubbe"
```

Or directly with home-manager:

```sh
home-manager switch --flake .#stubbe
```

## LAN NAMES AND SSH

Every machine publishes one mDNS name, `host.mdnsName` — `desktop.local` on
`stubbe-nixos`, `laptop.local` on the standalone host — and that value is fed
to avahi's `host-name`, so the name is the same on every interface instead of
whatever avahi's collision counter made it (`stubbe-nixos-5.local` and
friends).

`stubbe.lib.lanHosts` (`modules/core/lib/lan-hosts.nix`) is the catalogue of
those names and the users they log in as, and `~/.ssh/config` is generated
from it: `ssh laptop`, `ssh laptop.local`, `ssh desktop` and `ssh
desktop.local` all resolve, and completion lists them because zsh's
`_ssh_hosts` reads the file itself. Hosts that run avahi also publish
`_ssh._tcp`.

## ANDROID (NIX-ON-DROID)

`phone` is the same module set as every other host, built by the F-Droid
nix-on-droid app (the `nix-on-droid` flake input, `configurations.nixOnDroid`):

```sh
git clone --depth 1 https://github.com/stubbedev/dotfiles.git ~/.stubbe
cd ~/.stubbe && nix-on-droid switch --flake .#phone
```

After that first switch `hm switch` delegates to `nix-on-droid switch --flake
<flake>#phone`; `hm` finds that attribute through `host.flakeAttr`, since
neither the device's hostname nor `$USER` names anything in the flake.

Switched off there because proot has no display server, no D-Bus, no
init/systemd and no `/etc`: `desktop`, `theming`, `media`, `browsers`,
`slack`, `lysWm`, `lysShell`, `avahi`, `openssh`, `vpn`, `docker`, `srv`,
`treeman` and `php`. The shell, tmux and nvim configs are deliberately not
`features.desktop`-gated, so they come along.

Two things are worth knowing on the phone:

- **sops.** The phone shares the existing `~/.ssh/id_ed25519`, so its age
  recipient is the `stubbe` entry already in `.sops.yaml`: copy the key into
  the app's `~/.ssh/` (`chmod 600`), and the secrets aspect derives
  `~/.config/sops/age/keys.txt` from it at activation. A machine with its own
  key instead goes through `hm whoami` and `hm trust <name> <pubkey>`.
- **`.local` names.** nix-on-droid's glibc has no mDNS NSS module, no D-Bus to
  run avahi against and a hardcoded `resolv.conf`, so the phone cannot resolve
  `laptop.local` by name. Its ssh config uses `mdns-ssh` instead, which
  resolves the `_ssh._tcp` record the other hosts publish and relays the
  connection. `phone` does not publish anything, so the LAN cannot reach it.

`nixOnDroidConfigurations` is not an output `nix flake check` knows, so
`eval-nix-on-droid-phone` covers its home-manager half only; `user.uid`/`gid`
come from the device and need an aarch64 builder.

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

It partitions the disks as a btrfs volume, runs `nixos-install`, and clones the
repo to `/mnt/etc/nixos/dotfiles`.

Optional hardening is available behind per-host flags in the host file
(`modules/hosts/stubbe-nixos.nix`):

- **Secure Boot** (`host.secureBoot`) — lanzaboote signed bootloader; enroll
  keys with `sbctl` first.
- **Impermanence** (`host.impermanent`) — wipes `/` on every boot, keeping only
  paths declared in `modules/impermanence.nix`.

Both require setup steps before flipping the flag — see the comments in the
host file and module.

![Wallpaper preview](./src/wallpapers/traffic.png)
