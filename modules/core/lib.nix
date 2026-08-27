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
