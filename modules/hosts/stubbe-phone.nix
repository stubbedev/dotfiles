# Android: nix-on-droid inside the F-Droid Termux app. Inside the home-manager
# bridge it is the same module set as every other host; the mobile profile
# keeps it to the terminal set, since proot has no display server, no D-Bus,
# no init/systemd, no /etc and no setuid.
{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
{
  configurations.nixOnDroid.phone = {
    system = "aarch64-linux";
    module =
      { pkgs, ... }:
      {
        # nix-on-droid's own state version, whose enum stops at its last
        # release. It is unrelated to the nixpkgs pin and to
        # home.stateVersion.
        system.stateVersion = "24.05";

        environment.motd = null;

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

            host = {
              platform = "android";
              profile = "mobile";
            };
          };
        };
      };
  };
}
