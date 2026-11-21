# Android: nix-on-droid inside the F-Droid Termux app. Inside the home-manager
# bridge it is the same module set as every other host; the mobile profile
# keeps it to the terminal set, since proot has no display server, no D-Bus,
# no init/systemd, no /etc and no setuid. phix stands in for systemd's user
# manager (modules/scripts/phix.nix sets platform "android"), so the user
# units every host declares run here too.
{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
{
  configurations.nixOnDroid.phone = {
    system = "aarch64-linux";
    module =
      { config, pkgs, ... }:
      let
        # The machine that compiles this phone's closures: an x86_64 host that
        # emulates aarch64 (modules/hosts/desktop.nix), reached through the
        # same ssh alias every other host uses (modules/network.nix).
        buildHost = "desktop";
      in
      {
        # nix-on-droid's own state version, whose enum stops at its last
        # release. It is unrelated to the nixpkgs pin and to
        # home.stateVersion.
        system.stateVersion = "24.05";

        environment.motd = null;

        android-integration.termux-wake-lock.enable = true;

        nix.package = pkgs.nixVersions.nix_2_34;

        # nix-on-droid writes /etc/nix/nix.conf itself, with only the upstream
        # caches. Without our substituters every overlay and flake-input package
        # (phix, shell-lsp, the nvim wrapper) has to be fetched from a host that
        # does have it or compiled here.
        nix = {
          inherit (pkgs.stubbe.cache) substituters;
          trustedPublicKeys = pkgs.stubbe.cache.trusted-public-keys;

          # A cold build here is hours of rustc/go on a phone; the desktop runs
          # it under emulation instead. `builders-use-substitutes` makes the
          # desktop fetch inputs from the binary caches rather than receive them
          # back over ssh from here, and an unreachable builder just falls back
          # to a local build.
          extraOptions = ''
            builders = ssh-ng://${buildHost} aarch64-linux ${config.user.home}/.ssh/id_ed25519 8 4 big-parallel
            builders-use-substitutes = true
          '';
        };

        terminal.font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf";

        user = {
          # zsh, with the same config every other host gets: nix-on-droid
          # otherwise logs in to bash. uid/gid are deliberately left at their
          # defaults, derived from `id` on the device at build time.
          shell = "${pkgs.zsh}/bin/zsh";
        };

        home-manager = {
          # Reuse the pkgs above, so the phone gets this repo's overlays and
          # nixpkgs config, and install home.packages through nix-on-droid's
          # profile instead of a second, separate one.
          useGlobalPkgs = true;
          useUserPackages = true;
          config = {
            imports = builtins.attrValues homeModules;

            nix.package = config.nix.package;

            host = {
              platform = "android";
              profile = "mobile";
            };
          };
        };
      };
  };
}
