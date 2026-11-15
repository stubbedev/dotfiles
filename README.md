# STUBBEDEV DOTFILES

Personal dotfiles and utilities, bundled as a Nix flake with an installer and
a maintenance front-end. It builds two NixOS machines and an Android phone
(nix-on-droid); home-manager runs inside each of them.

The helpers for running home-manager on a non-NixOS distro (privileged `/etc`
installs at activation time, GL/Vulkan wrapping against the host driver) were
extracted into their own library:
[stubbedev/hm-distro](https://github.com/stubbedev/hm-distro).

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
│   └── <aspect>.nix       # mail, shell, lys-wm, lys-shell, power, storage, …
├── bin/                   # ONLY the live-ISO installer (stb-install-nixos)
├── src/                   # the few real files: the nvim live-edit
│                          # tree, aerc stylesets, wallpapers
├── certs/                 # the srv root CA (public cert); seeded into the
│                          # system trust store at build time
└── secrets/               # sops-encrypted, keyed per machine in .sops.yaml
```

Every config file and script is inline Nix inside its aspect module. Scripts
become PATH bins through `pkgs.stubbe.bashApp` (build-time `shell-lsp check`),
`pkgs.stubbe.zshApp` (build-time `zsh -n`), or `pkgs.stubbe.shellScript` /
`shellScriptBin` for scripts that must keep plain (non-`set -euo pipefail`)
semantics. `bin/stb-install-nixos` is baked into the installer ISO.

## CONVENTIONS

1. **One file, one aspect, both classes.** Every file under `modules/`
   registers under `flake.modules.homeManager.<aspect>` and/or
   `flake.modules.nixos.<aspect>`. Values shared between the two halves are
   let-bound at the top of the file, so the system and user halves cannot
   drift apart. Hosts import a whole class with
   `builtins.attrValues`; nothing references a module by name.

2. **No opt-outs.** Every `.nix` file under `modules/` is auto-loaded by
   import-tree and must be a flake-parts module. There are no
   underscore-prefixed exceptions.

3. **Three layers of shared code, and no fourth.**
   - `stubbe.lib.*` (`modules/core/lib/`) — pure data and pure functions:
     `colors`, `theme`, `newtabUrl`, `cache`, the `hm` command catalogue,
     `managedBy`. Needs nothing; mirrored as `flake.lib`.
   - `pkgs.stubbe.*` (`modules/core/pkgs/`) — every builder that needs `pkgs`:
     `secret`, `bashApp`, `zshApp`, `shellScript`, `gen`, `wrapPackage`,
     `withDriverLibs`, `check`, and the `setup.json*` script fragments. Re-exports all of
     `stubbe.lib`, and is reachable from any module of any class because it
     rides on `pkgs`.
   - `config.stubbe.*` — options for anything derived from the evaluated
     configuration: `paths`, `setup`, `mutable`, `userFeatures`.

   There is no `specialArgs` and no `extraSpecialArgs` anywhere. A module that
   needs a flake input resolves it at flake-parts level, where `inputs` is
   already in scope. This is what makes every aspect movable between the
   targets without rewiring.

4. **Feature gates and the platform split.** Behaviour toggles are
   `features.*` options (`modules/core/features.nix`), gated with
   `lib.mkIf config.features.<x>`. NixOS aspects gate on
   `config.stubbe.userFeatures.<x>`, the same flags resolved once from the
   primary user. `host.platform` is `nixos` or `android`: the NixOS half owns
   all system state, and on Android (proot, no init, no D-Bus) the aspects
   that need a system service or a systemd unit gate themselves off.

5. **Activation steps.** `stubbe.setup.<name>` (`modules/core/setup.nix`) is
   the one way to run imperative, user-level work at switch time. The
   attribute name is the DAG node name. Anything that touches `/etc` belongs in
   the aspect's NixOS half instead.

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
   ones that must be files: the nvim live-edit tree
   (`stubbe.mutable` link), binary wallpapers, and the sops secrets.

## APPLYING THE CONFIG

Day-to-day rebuilds run through `hm`, which wraps `nixos-rebuild` on NixOS and
`nix-on-droid` on the phone, against the checkout linked at `~/.stubbe`:

```sh
hm switch      # build and activate
hm upgrade     # update flake inputs, commit flake.lock, switch
hm help        # every verb
```

## NIXOS HOSTS

`modules/hosts/` holds one file per machine, each a handful of host facts:

| Host      | Hardware                     | Disk                                          |
| --------- | ---------------------------- | --------------------------------------------- |
| `desktop` | NVIDIA                       | btrfs, persistent root                        |
| `laptop`  | ThinkPad X1 Carbon (battery) | LUKS2 + btrfs, root rolled back on every boot |

The attribute name doubles as the machine's LAN name (`desktop.local`,
`laptop.local`), and the facts a host sets (`host.battery`,
`host.graphicsNvidia`, …) reach its home-manager half unchanged.

The disk layout is derived from the host flags in `config.stubbe.storage`
(`modules/storage.nix`), which both the mounts and the installer read:

- **`host.luks`** puts the btrfs volume in a LUKS2 container, unlocked by
  passphrase in the initrd. TPM2 unlock can be added later without
  reinstalling: turn on Secure Boot, then `systemd-cryptenroll
  --tpm2-device=auto` the data partition.

Every installed host is impermanent: the root subvolume is rolled back to an
empty snapshot on every boot, and `/var` lives on it, so only what
`modules/impermanence.nix` persists under `/persist` survives: the flake
checkout, logs, network, bluetooth, fingerprints, docker, … `/home` and `/nix`
are their own subvolumes and unaffected. Users are immutable; change the
password by writing a new hash to `/persist/passwords/<user>`.

- **`host.secureBoot`** swaps systemd-boot for lanzaboote; enroll keys with
  `sbctl` first.

## ANDROID HOST

`modules/hosts/stubbe-phone.nix` defines `nixOnDroidConfigurations.phone`: the
[nix-on-droid](https://github.com/nix-community/nix-on-droid) app running a
proot'd Nix on Android. Its home-manager half imports the same module set as
the NixOS hosts with `host.platform = "android"` and `host.profile =
"mobile"`, so every `features.*` flag defaults to the terminal set: zsh, tmux,
nvim, git and ssh, nothing that needs a display, D-Bus or systemd. On the
phone, `hm switch` runs `nix-on-droid switch --flake ~/.stubbe#phone`.

## INSTALLING NIXOS

Build a bootable installer ISO:

```sh
nix build .#installer-iso --impure
# Output: ./result/iso/*.iso — flash to a USB stick.
```

Boot the live USB on the target, log in as `root`, and run:

```sh
stb-install-nixos
```

It asks which host to install, lays the disk out from that host's
configuration, runs `nixos-install`, and clones the repo to
`/etc/nixos/dotfiles`. After first boot, trust the new host key so system
secrets decrypt: the installer prints the exact `hm trust` command.

### MOVING A MACHINE

Your repositories move across a reinstall without re-cloning, mirrored to
another machine over ssh (or to a local ext4/btrfs drive):

```sh
stb-migrate backup desktop.local:migrate    # before wiping; rerun to send only changes
stb-migrate restore desktop.local:migrate   # after the reinstall
```

`backup` mirrors `~/git`, `~/.ssh` and `~/.gnupg`, everything included, into
`<dest>/<hostname>/`. `restore` copies it back and never overwrites a file that
already exists. The srv proxies and redirects are declared in
`modules/srv.nix`, and its CA key is held in sops, so srv rebuilds itself on
the first `hm switch`.

![Wallpaper preview](./src/wallpapers/traffic.png)
