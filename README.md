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
├── lib/                   # extra shared libs (system-info)
├── constants.nix          # path constants (paths.dotfiles, paths.shared, ...)
├── gfx.nix
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
│   ├── stb*  stb-install*
│   ├── fzf-*  tmux-*
│   └── ...
├── src/
│   ├── _shared/scripts/   # cross-app scripts (waybar.launch.sh, monitor.brightness.sh, ...)
│   ├── aerc/  alacritty/  btop/
│   ├── hypr/  niri/  waybar/
│   ├── ...
│   └── zsh/
└── README.md
```

The bin directory contains `stb` and `stb-install` which are the 2 utility
binaries. It may also contain other utilities binaries if directly included in
the repo.

In the `src` directory we find various applications, each with their own
directory. If an application such as `zsh` or `golang` install more packages,
they are placed in a child directory of that plugin.

## INSTALLATION

In order to install the utils and config, you simply need to run the following
command:

`git clone --depth 1 git@github.com:stubbedev/dotfiles.git && cd dotfiles && ./bin/stb-install`

The installer will prompt you with options on what to install.

After installation you can use the `stb` followed by an option to add stuff to
your config.

If you provide no option the wizard will list the available options.

## APPLYING THE NIX/HOME-MANAGER CONFIG

The flake lives at the repo root. Apply with:

`hm switch --flake "path:$HOME/.stubbe"`

Or directly with home-manager:

`home-manager switch --flake .#stubbe --impure`

The `--impure` is required because activation scripts read `$HOME` and detect
the host distribution at evaluation time.

![This is the caption for the next figure link (or table)](./src/wallpapers/traffic.png)
