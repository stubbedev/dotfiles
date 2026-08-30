# `config.stubbe.lib` — the repo's single source of truth for pure data and
# pure functions. Nothing here touches `pkgs` or a module `config`, so it is
# safe to read from any class (nixos, homeManager) and from flake-level code
# (the checks, the installer ISO).
#
# Modules do NOT read this directly: modules/core/pkgs-stubbe.nix re-exports the
# whole thing as `pkgs.stubbe`, alongside the builders that do need `pkgs`.
# Inside a module, reach for `pkgs.stubbe.<x>`; at flake-parts level, for
# `config.stubbe.lib.<x>`. There is no third way, and no `specialArgs`.
#
# Why a plain flake-parts option rather than `flake.lib` alone: `flake.lib` is a
# freeform flake output, and reading a freeform attr forces the whole `flake`
# submodule — including the transposed perSystem outputs, which need `pkgs`,
# which is built from the overlays that read this. That is an infinite
# recursion. A declared top-level option has no such dependency, so it is what
# the overlay reads; `flake.lib` below is only the outward-facing mirror.
{
  config,
  self,
  lib,
  ...
}:
{
  options.stubbe.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Pure data and pure functions shared across every class. Re-exported as `pkgs.stubbe`.";
  };

  config.flake.lib = config.stubbe.lib;

  config.stubbe.lib = {
    # Repo source root. Baked here so no module needs `self` injected.
    src = self;

    # Catppuccin Mocha (hex, no leading #). Every themed surface derives its
    # colours from this one attrset — see `toHex`/`toRgb`/`toArgb` below for
    # the per-format renderers, so a palette swap never needs a hand-edit in
    # a .theme / .rasi / .lua / .css file.
    colors = {
      rosewater = "f5e0dc";
      flamingo = "f2cdcd";
      pink = "f5c2e7";
      mauve = "cba6f7";
      red = "f38ba8";
      maroon = "eba0ac";
      peach = "fab387";
      yellow = "f9e2af";
      green = "a6e3a1";
      teal = "94e2d5";
      sky = "89dceb";
      sapphire = "74c7ec";
      blue = "89b4fa";
      lavender = "b4befe";
      text = "cdd6f4";
      subtext1 = "bac2de";
      subtext0 = "a6adc8";
      overlay2 = "9399b2";
      overlay1 = "7f849c";
      overlay0 = "6c7086";
      surface2 = "585b70";
      surface1 = "45475a";
      surface0 = "313244";
      base = "1e1e2e";
      mantle = "181825";
      crust = "11111b";
    };

    # Theme names referenced across modules. Kept in lockstep with what
    # modules/theming.nix actually selects; pure strings, so both classes read
    # them the same way (`pkgs.stubbe.theme.<x>`).
    theme = {
      icon = "Tela-circle-purple-dark";
      cursor = "Vimix-cursors";
      cursorSize = 24;
      gtk = "catppuccin-mocha-mauve-standard";
      kvantum = "Catppuccin-Mocha-Mauve";
      sddm = "catppuccin-mocha-mauve";
      plymouth = "catppuccin-mocha";
    };

    # Canonical URL of the local new-tab / new-window page. `srv` serves it as
    # a static site at https://start.local (registered once with `srv add` —
    # see the README). A file:// page can't be used: Tridactyl's `set newtab`
    # double-opens file:// URLs (tridactyl#530); serving over https also gives
    # one URL that works for both Firefox and Chrome. Shared so tridactylrc,
    # the Firefox Homepage policy and the Chrome enterprise policy all agree.
    newtabUrl = "https://start.local/";

    # Binary caches, read by the NixOS daemon (modules/nix.nix) and by
    # standalone-HM's user-mode nix on non-NixOS hosts.
    #
    # All first-party closures (stubbe HM + NixOS, plus wayle/treeman/srv/…)
    # live in one xilo cache — `default` in the `default` namespace, hence
    # /c/default/default. `hm switch` substitutes the heavy first-party builds
    # from here instead of compiling locally; whichever machine compiles a
    # path pushes it back (see the hm script in modules/scripts.nix). Everything is signed by the single
    # `default:` key below.
    cache = {
      substituters = [
        "https://nix.stubbe.dev/c/default/default"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "default:6uWvXutL9cXjV3lii+Ur5ff+ArQoG4kMBKNXWrIxhHg="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    # The `hm` CLI surface, as data. Before this the same verb list was written
    # out by hand four times — the dispatch `case`, the `usage()` heredoc and
    # the "supported subcommands" error in modules/scripts.nix, plus the zsh
    # `_hm` completion in modules/shell.nix — and had already drifted: the
    # completion offered `hm cache zsh` and `hm search`, neither of which the
    # wrapper implements. Everything except the dispatch `case` now renders
    # from this one table, via the `hm.render*` helpers below.
    #
    # Per command:
    #   platform  "all" | "nixos" | "standalone" — where the verb actually works.
    #             Drives both the completion arrays and the NixOS error message.
    #   group     "wrapper"  verbs this script implements itself
    #             "rebuild"  verbs routed to nh / nixos-rebuild / home-manager
    #             "meta"     help
    #             "hidden"   proxied straight to the home-manager CLI; completed
    #                        but deliberately absent from `hm help`
    #   syntax    help-row left column; defaults to the name
    #   extra     continuation lines under the help row
    #   sub       second-level names, for completion and for the sub-command's
    #             own usage text; `expand` gives each one its own help row
    #   complete  "custom" when _hm has a hand-written branch for its arguments;
    #             everything else takes no completable arguments
    hm =
      let
        cmd =
          {
            name,
            platform,
            group,
            desc,
            summary ? desc,
            syntax ? name,
            extra ? [ ],
            sub ? null,
            expand ? false,
            complete ? null,
          }:
          {
            inherit
              name
              platform
              group
              desc
              summary
              syntax
              extra
              sub
              expand
              complete
              ;
          };
        # Order is the order `hm help` prints; the completion does not care.
        commands = map cmd [
          {
            name = "update";
            platform = "all";
            group = "wrapper";
            desc = "Update system package managers and nix inputs";
          }
          {
            name = "upgrade";
            platform = "all";
            group = "wrapper";
            desc = "Update system packages and apply switch (auto-prunes";
            extra = [ "old generations, keeping current + 1 previous)" ];
            summary = "Update system packages and apply switch";
          }
          {
            name = "whoami";
            platform = "all";
            group = "wrapper";
            desc = ''Print "<hostname> <age-pubkey>" for this machine'';
          }
          {
            name = "trust";
            syntax = "trust [name] <key>";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Add an age recipient to .sops.yaml and re-wrap secrets/*";
            summary = "Add an age recipient to .sops.yaml and re-wrap secrets/*";
            extra = [
              "- hm trust <name> <pubkey>"
              "- hm trust <pubkey>           (auto-named)"
              "- cmd | hm trust              (e.g. ssh other hm whoami | hm trust)"
            ];
          }
          {
            name = "secret";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            expand = true;
            desc = "Edit, set, or rotate an encrypted file under secrets/";
            sub = [
              {
                name = "edit";
                syntax = "edit <name>";
                desc = "Open secrets/<name> in $EDITOR via sops, binary mode (creates if absent)";
              }
              {
                name = "set";
                syntax = "set <name>";
                desc = "Replace secrets/<name> with a new value (prompts on TTY, reads stdin otherwise)";
              }
              {
                name = "rotate";
                syntax = "rotate <name>";
                desc = "Re-roll the data key for secrets/<name>, recipients unchanged";
              }
            ];
          }
          {
            name = "cache";
            syntax = "cache <target>";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Wipe cached state (target: nvim|locks|all)";
            sub = [
              {
                name = "nvim";
                desc = "Clear ~/.local/{share,state}/nvim and ~/.cache/nvim";
              }
              {
                name = "locks";
                desc = "Wipe ~/.local/state/nix/home-manager/*.lock.sum so every";
                extra = [ "privileged activation re-runs on next switch" ];
                summary = "Wipe ~/.local/state/nix/home-manager/*.lock.sum (re-runs every gated activation)";
              }
              {
                name = "all";
                desc = "nvim. Does NOT touch locks — that's intentional";
                extra = [ "(re-runs every gated activation; opt-in only)" ];
                summary = "nvim. Does NOT touch locks — that is opt-in only";
              }
            ];
          }
          {
            name = "clean";
            syntax = "clean [dir]";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Interactive fzf TUI to scan/reclaim disk space: build";
            summary = "Interactive TUI to scan/reclaim disk space (build dirs, caches, core dumps, nix gc)";
            extra = [
              "dirs (node_modules, target, .next, dist, vendor,"
              ".venv), ~/.cache subdirs, ~/core dumps, and nix gc."
              "Scans [dir] (default $HOME). Nothing deleted without"
              "confirmation."
            ];
          }
          {
            name = "iso";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            expand = true;
            desc = "Build the NixOS installer ISO or burn it to a USB device";
            sub = [
              {
                name = "build";
                syntax = "build [args]";
                desc = "Build the installer ISO with --impure";
              }
              {
                name = "path";
                syntax = "path [args]";
                desc = "Build the ISO and print the output path";
              }
              {
                name = "devices";
                desc = "List removable/block devices";
              }
              {
                name = "burn";
                syntax = "burn <device> --yes";
                desc = "Build the ISO and write it to a USB device";
              }
              {
                name = "help";
                desc = "Show nixos-iso help";
              }
            ];
          }

          {
            name = "switch";
            platform = "all";
            group = "rebuild";
            desc = "Build and activate (default boot entry on NixOS);";
            extra = [ "auto-prunes old generations to current + 1 previous" ];
            summary = "Build and activate the configuration";
          }
          {
            name = "boot";
            platform = "nixos";
            group = "rebuild";
            desc = "Build and set as next-boot only (NixOS)";
          }
          {
            name = "test";
            platform = "nixos";
            group = "rebuild";
            desc = "Activate without making it the default (NixOS)";
          }
          {
            name = "build";
            platform = "all";
            group = "rebuild";
            desc = "Build without activating";
          }
          {
            name = "dry-build";
            platform = "nixos";
            group = "rebuild";
            desc = "Show what would build, don't fetch/build";
          }
          {
            name = "dry-activate";
            platform = "nixos";
            group = "rebuild";
            desc = "Show what activate would do, don't activate (NixOS)";
          }
          {
            name = "build-vm";
            platform = "nixos";
            group = "rebuild";
            desc = "Build a VM image of the configuration (NixOS)";
          }
          {
            name = "build-vm-with-bootloader";
            platform = "nixos";
            group = "rebuild";
            desc = "Same, including bootloader (NixOS)";
          }
          {
            name = "repl";
            platform = "nixos";
            group = "rebuild";
            desc = "Open a nix repl scoped to the configuration (NixOS)";
          }
          {
            # Standalone home-manager has no rollback verb — run_rollback prints
            # the `<gen>/activate` recipe and exits 2 — so it is not offered there.
            name = "rollback";
            platform = "nixos";
            group = "rebuild";
            desc = "Roll back to the previous generation";
          }
          {
            name = "generations";
            platform = "all";
            group = "rebuild";
            desc = "List system/home-manager generations";
          }
          {
            name = "gc";
            syntax = "gc [args]";
            platform = "all";
            group = "rebuild";
            complete = "custom";
            desc = "No args: nh clean (all profiles + gcroots + store gc).";
            extra = [ "With args: nix-collect-garbage <args>." ];
            summary = "No args: nh clean; with args: nix-collect-garbage <args>";
          }
          {
            name = "news";
            platform = "standalone";
            group = "rebuild";
            desc = "Read home-manager release notes (non-NixOS)";
          }
          {
            name = "instantiate";
            platform = "standalone";
            group = "rebuild";
            desc = "home-manager instantiate (non-NixOS)";
          }
          {
            name = "help";
            platform = "all";
            group = "meta";
            desc = "Show this help message";
          }

          # Reached only through the wrapper's `*` fallthrough, which proxies to
          # the home-manager CLI. Completed so the verbs are discoverable, but
          # kept out of `hm help`: they are home-manager's surface, not ours.
          {
            name = "edit";
            platform = "standalone";
            group = "hidden";
            desc = "Open the home configuration in $VISUAL or $EDITOR";
          }
          {
            name = "option";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Inspect configuration option";
          }
          {
            name = "init";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Initialize a configuration in the given directory";
          }
          {
            name = "remove-generations";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Remove indicated generations";
          }
          {
            name = "expire-generations";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Remove generations older than timestamp";
          }
          {
            name = "packages";
            platform = "standalone";
            group = "hidden";
            desc = "List all packages installed in home-manager-path";
          }
          {
            name = "uninstall";
            platform = "standalone";
            group = "hidden";
            desc = "Remove Home Manager";
          }
        ];

        byName =
          name: lib.findFirst (c: c.name == name) (throw "stubbe.lib.hm: no such command ${name}") commands;
        pad = n: lib.concatStrings (lib.genList (_: " ") n);

        # `hm help` lays descriptions out in a column, with a two-space
        # minimum gap for the handful of verbs wider than it
        # (build-vm-with-bootloader is 24 characters on its own).
        descCol = 24;
        helpRow =
          syntax: desc: extra:
          let
            head = "  " + syntax;
          in
          lib.concatStringsSep "\n" (
            [ (head + pad (lib.max 2 (descCol - lib.stringLength head)) + desc) ]
            ++ map (l: pad (descCol + 2) + l) extra
          );

        # zsh `_describe` reads 'value:description' pairs from a single-quoted
        # array, so an apostrophe in a description has to close and reopen the
        # quote. "this machine's key" is the only one today, but the whole
        # point of this table is that the next one cannot get it wrong.
        zshQuote = s: "'" + lib.replaceStrings [ "'" ] [ "'\\''" ] s + "'";
        # A completion menu gets one line per entry, so `desc` + `extra` — which
        # exist to lay `hm help` out over several — are not usable there.
        # `summary` defaults to `desc` and is set explicitly by the entries whose
        # `desc` is only the first half of a sentence.
        zshRow = e: zshQuote "${e.name}:${e.summary or e.desc}";
      in
      {
        inherit commands;

        # `hm help`, `nixos-iso help` — the Commands: block, rows only.
        renderHelp =
          group:
          lib.concatMapStringsSep "\n" (c: helpRow c.syntax c.desc c.extra) (
            lib.filter (c: c.group == group) commands
          );
        renderSubHelp =
          name:
          lib.concatMapStringsSep "\n" (s: helpRow (s.syntax or s.name) s.desc (s.extra or [ ]))
            (byName name).sub;

        # `hm secret` etc.: sub-commands expanded into their own help rows,
        # prefixed by the parent verb.
        renderExpandedHelp =
          group:
          lib.concatMapStringsSep "\n" (
            c:
            if c.expand then
              lib.concatMapStringsSep "\n" (
                s: helpRow "${c.name} ${s.syntax or s.name}" s.desc (s.extra or [ ])
              ) c.sub
            else
              helpRow c.syntax c.desc c.extra
          ) (lib.filter (c: c.group == group) commands);

        # zsh completion arrays. `platform` selects one of the three blocks
        # `_hm` assembles at runtime from /etc/os-release. `indent` is the
        # generated file's own indentation at the call site — Nix strips the
        # common indent of an `''` string's literal lines, but interpolated
        # newlines come through at column zero, so each renderer re-applies it.
        renderZsh =
          indent: platform:
          lib.concatMapStringsSep "\n${indent}" zshRow (lib.filter (c: c.platform == platform) commands);
        renderSubZsh = indent: name: lib.concatMapStringsSep "\n${indent}" zshRow (byName name).sub;

        # `_hm`'s catch-all branch: every verb without a hand-written
        # argument-completion branch, as a zsh case pattern.
        plainVerbs = lib.concatMapStringsSep "|" (c: c.name) (
          lib.filter (c: c.complete == null && c.sub == null) commands
        );

        # "switch, boot, test, …" for the wrapper's NixOS error message, and
        # "edit|set|rotate" / "nvim|locks|all" for the sub-command usages.
        nixosVerbs = lib.concatMapStringsSep ", " (c: c.name) (
          lib.filter (c: c.group == "rebuild" && c.platform != "standalone") commands
        );
        subNames = name: lib.concatMapStringsSep "|" (s: s.name) (byName name).sub;
      };

    # nixpkgs instantiation args, shared verbatim by the standalone-HM pkgs
    # (modules/core/flake.nix) and by NixOS's `nixpkgs.config`
    # (modules/nix.nix) so both targets resolve packages identically.
    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "dcraw-9.28.0"
        "pnpm-10.34.0"
      ];
    };
  };
}
