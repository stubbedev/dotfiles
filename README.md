# STUBBEDEV DOTFILES

<!--toc:start-->
- [STUBBEDEV DOTFILES](#stubbedev-dotfiles)
  - [STRUCTURE](#structure)
  - [INSTALLATION](#installation)
<!--toc:end-->

This is a collection of personal dotfiles and utilities I use on linux. They are
bundled as an installer and a maintenance utility.

## STRUCTURE

The dotfiles and utilities are stored and applied in a way where they try to be
as self contained as possible. The main way I try to achieve this is by creating
a directory `~/.stubbe` and symlinking this git repository to that path. This
means that all settings should be removed together with the utils from your
system, if you delete the repo.

The structure is as follows:

```tree
.stubbe/
├── flake.nix              # dendritic flake-parts entrypoint
├── flake.lock
├── lib.nix                # shared lib helpers (xdgSource, sudoPromptScript, ...)
├── lib/                   # extra shared libs (gfx wrappers, plymouth theme, mcp servers, nix cache, system-info)
├── constants.nix          # path + theme constants (paths.dotfiles, theme.icon, ...)
├── modules/               # dendritic modules tree (auto-loaded via import-tree)
│   ├── activation/        # home-manager activation scripts (privileged + non-privileged)
│   ├── files/             # home.file declarations
│   ├── home/              # home-manager core (context, systemd, xdg, ...)
│   ├── home-manager/      # home configurations + pkgs
│   ├── hosts/             # per-host definitions
│   ├── packages/          # package sets
│   ├── programs/          # programs.* declarations
│   ├── theme/
│   └── features.nix
├── bin/
│   ├── hm*                # home-manager / nixos-rebuild front-end (templated)
│   ├── nixos-iso*         # build / burn the installer ISO (templated)
│   ├── stb-install*       # bootstrap (run from the checkout, before Nix exists)
│   ├── stb-install-nixos* # ISO-resident NixOS installer
│   ├── tmux-*             # tmux launcher wrappers
│   ├── tmux-pick-*        # interactive tmux picker (fzf+tmux)
│   └── fzf-pick-*         # headless fzf pickers (return a string)
├── src/
│   ├── _shared/scripts/   # cross-app scripts (waybar.launch.sh, monitor.brightness.sh, ...)
│   ├── aerc/  alacritty/  btop/
│   ├── hypr/  niri/  waybar/
│   ├── ...
│   └── zsh/
└── README.md
```

The `bin/` directory holds the source for shell scripts that get built into
Nix-managed binaries under `~/.nix-profile/bin/` via `modules/home/scripts.nix`.
`stb-install` is the only one that actually runs from the checkout: it's the
bootstrap that brings Nix and home-manager up on a fresh non-NixOS host.

In the `src` directory we find various applications, each with their own
directory. If an application such as `zsh` or `golang` install more packages,
they are placed in a child directory of that plugin.

## INSTALLATION

In order to install the utils and config, you simply need to run the following
command:

`git clone --depth 1 git@github.com:stubbedev/dotfiles.git && cd dotfiles && ./bin/stb-install`

The installer will prompt you with options on what to install. Once Nix and
home-manager are up, day-to-day rebuilds run through `hm` (see below).

## APPLYING THE NIX/HOME-MANAGER CONFIG

The flake lives at the repo root. Apply with:

`hm switch --flake "path:$HOME/.stubbe"`

Or directly with home-manager:

`home-manager switch --flake .#stubbe --impure`

The `--impure` is required because activation scripts read `$HOME` and detect
the host distribution at evaluation time.

## NIXOS INSTALLER ISO

Build a bootable installer ISO that mirrors the `stubbe-nixos` host:

```sh
# Recommended: scope which SSH keys get baked into the ISO.
STB_ISO_SSH_KEYS=id_ed25519:id_ed25519.pub:known_hosts \
  nix build .#installer-iso --impure

# Output: ./result/iso/*.iso — flash to a USB stick with `dd` or
# (on NixOS) `nixos-rebuild boot --target-host live-iso`.
```

> **Security:** the ISO contains your private SSH keys (used by
> `bin/stb-install-nixos` to clone this repo onto the target).
> Treat the image as sensitive — never publish or share it, and wipe
> the install USB once the target machine is up.

Boot the live USB on the target machine, log in as `root` (auto-login on
tty1), and run:

```sh
stb-install-nixos
```

The script wipes every fixed (non-removable) disk, formats them as a
multi-device btrfs volume labeled `stubbe`, runs
`nixos-install --flake /etc/nixos#stubbe-nixos`, clones this repo to
`/mnt/etc/nixos` over SSH, and prompts for the primary user's password
before finishing.

### Optional: Secure Boot (lanzaboote)

After first boot, replace systemd-boot with the lanzaboote signed
bootloader so the firmware verifies every kernel + initrd signature:

```sh
# 1. Put the firmware in Secure Boot setup mode (UEFI menu → Security →
#    Secure Boot → Reset / Clear keys). Verify with `sudo sbctl status`:
sudo sbctl status            # Expect: "Setup Mode: Enabled"

# 2. Generate platform keys + enroll Microsoft + custom keys.
sudo sbctl create-keys
sudo sbctl enroll-keys --microsoft

# 3. Flip the host flag and rebuild.
# In modules/nixos/hosts/stubbe-nixos.nix add:  host.secureBoot = true;
sudo nixos-rebuild switch --flake /etc/nixos#stubbe-nixos
sudo sbctl verify           # Every closure path should report "signed"

# 4. Re-enable Secure Boot in firmware and reboot.
```

Skipping any step bricks boot; recover by booting a live ISO,
`mount -o subvol=@` the btrfs root, edit `flake.nix` / host file to
unset `host.secureBoot`, and `nixos-install` again.

### Optional: Impermanence

The installer always creates an `@-blank` snapshot of the empty `@`
subvol before populating it. To activate root-on-boot rollback (so
every boot starts from a wiped `/`, with only paths declared in
`modules/nixos/impermanence.nix` surviving via `/persist`):

```sh
# 1. Verify @-blank exists.
sudo btrfs subvolume list /  | grep '@-blank'

# 2. Audit the persistence list at modules/nixos/impermanence.nix —
#    add anything host-specific (state directories, license files, …).

# 3. Flip the host flag and rebuild.
# In modules/nixos/hosts/stubbe-nixos.nix add:  host.impermanent = true;
sudo nixos-rebuild boot --flake /etc/nixos#stubbe-nixos
sudo reboot
```

After the first impermanent boot, anything in `/` that isn't covered
by the persistence list is gone. State you forgot to declare can be
recovered from `/persist/old/` on the running system OR by mounting
`@-blank`'s pre-rollback parent (the previous boot's `@-old` if you
keep one) — neither is automatic; treat the audit step as mandatory.

## BROWSER NEW-TAB PAGE

The minimal new-tab / new-window page (`src/browser/newtab.html`) is
installed by home-manager to `~/.local/share/stubbedev/newtab/` and is
served by `srv` as a static site at `https://start.local`. Firefox
(Tridactyl `set newtab` + the Homepage policy) and Chrome (enterprise
policy) all point there — a file:// page can't be used because
Tridactyl's `set newtab` double-opens file:// URLs (tridactyl#530).

A non-privileged activation
(`modules/activation/_non-privileged/setup-srv-newtab.nix`) registers the
site with `srv` automatically on `home-manager switch` — idempotent, and
skipped once it is registered. It does need `srv install` (Docker,
Traefik, mkcert) to have been run once first; until then the activation
skips quietly and retries on the next switch. The equivalent manual
command is:

```sh
srv add ~/.local/share/stubbedev/newtab --domain start.local --local
```

`--local` issues a mkcert certificate; srv re-serves the site on boot,
and page edits land on the next switch with no re-run (srv serves the
directory live).

## SURFINGKEYS (CHROME) SETUP

The SurfingKeys extension is force-installed and its config is written
by home-manager (`modules/packages/chrome/surfingkeys.nix` →
`~/.config/surfingkeys/config.js`). Two one-time steps remain — Chrome
deliberately walls these off from policy, so they cannot be automated.
They persist in the profile afterwards, surviving updates and rebuilds.

```
1. chrome://extensions → SurfingKeys → Details →
   enable "Allow access to file URLs".
   (Needed so SurfingKeys can read config.js from a file:// URL.)

2. Open SurfingKeys' settings (toolbar icon → SurfingKeys settings) and
   set "Load settings from:" to the absolute file URL:
       file:///home/stubbe/.config/surfingkeys/config.js
```

Tridactyl on Firefox needs no equivalent steps — its add-on, native
messenger and `tridactylrc` are all managed declaratively.

![This is the caption for the next figure link (or table)](./src/wallpapers/traffic.png)
