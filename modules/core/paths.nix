# Well-known paths, as options rather than an ad-hoc `constants.nix` imported
# through `_module.args`. Being options means they are typed, overridable
# per host, documented in `man home-configuration.nix`, and readable with
# `nix eval .#homeConfigurations.stubbe.config.stubbe.paths`.
_: {
  flake.modules.homeManager.paths =
    { config, lib, ... }:
    {
      options.stubbe.paths = {
        dotfiles = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.stubbe";
          defaultText = "\${config.home.homeDirectory}/.stubbe";
          description = ''
            The live checkout of this repo. Anything under
            `stubbe.mutable.<target>.src` resolves relative to `<dotfiles>/src`,
            and the scripts that must survive a `nix-collect-garbage` (the
            greetd launcher, the Hyprland script dir) reference it instead of a
            store path.
          '';
        };

        nixBin = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.profileDirectory}/bin";
          defaultText = "\${config.home.profileDirectory}/bin";
          description = ''
            Where Nix-installed binaries land: ~/.nix-profile/bin under
            standalone home-manager, /etc/profiles/per-user/$USER/bin under
            NixOS with useUserPackages.
          '';
        };

        terminal = lib.mkOption {
          type = lib.types.str;
          default = "${config.stubbe.paths.nixBin}/alacritty";
          defaultText = "\${config.stubbe.paths.nixBin}/alacritty";
          description = "Absolute path to the terminal emulator, for callers that cannot rely on PATH.";
        };

        wallpaper = lib.mkOption {
          type = lib.types.str;
          default = "${config.stubbe.paths.dotfiles}/src/wallpapers/ballet.jpg";
          defaultText = "\${config.stubbe.paths.dotfiles}/src/wallpapers/ballet.jpg";
          description = ''
            Desktop wallpaper, single source of truth: wayle-launch applies it
            to every monitor at startup and it is exported as the WALLPAPER
            session variable, so the DRM-hotplug listener re-applies it on dock
            without hardcoding a second copy of the path.
          '';
        };
      };
    };
}
