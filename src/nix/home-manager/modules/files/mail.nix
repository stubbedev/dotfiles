_: {
  flake.modules.homeManager.filesMail =
    {
      constants,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file = {
        ".local/bin/open-mail" = {
          text = ''
            if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
              hyprctl dispatch exec "${constants.paths.term} -e aerc"
            else
              ${constants.paths.term} -e aerc
            fi
          '';
          executable = true;
        };
        ".local/bin/unsubscribe-mail".source = ../../../../aerc/scripts/unsubscribe;
        ".w3m".source = ../../../../w3m;
      };
    };
}
