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
            lys-wm script dir) reference it instead of a store path.
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

        hostPath = lib.mkOption {
          type = lib.types.str;
          default =
            if config.host.platform == "nixos" then
              "/run/wrappers/bin:/run/current-system/sw/bin"
            else
              "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          defaultText = lib.literalMD "the NixOS system profile and setuid wrappers on NixOS, the FHS bin dirs elsewhere";
          description = ''
            The host's own executables, for units and activation steps whose
            programs shell out to tools the host provides (docker, sudo,
            certutil) and so cannot run on the stripped PATH they start with.
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
          default = "${../../src/wallpapers/ballet.jpg}";
          defaultText = "src/wallpapers/ballet.jpg, copied to the store";
          description = ''
            Desktop wallpaper, single source of truth: lys-shell's wallpaper, its
            lock screen and the lys-login greeter all read it. A store path, so
            the greeter's lys-greeter user can read it outside the 0700 home.
          '';
        };
      };
    };
}
