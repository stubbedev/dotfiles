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
            #!/usr/bin/env bash
            # Focus an existing aerc window if one is open, otherwise spawn a new
            # alacritty for it. The window is launched with --class so we can
            # match by app-id/class, which (unlike the title) stays stable as
            # aerc updates the displayed folder/count.
            APP_ID="aerc-mail"

            if [[ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]] && command -v hyprctl &> /dev/null; then
              addr=$(hyprctl -j clients | jq -r --arg c "$APP_ID" '.[] | select(.class == $c) | .address' | head -n1)
              if [[ -n "$addr" ]]; then
                hyprctl dispatch focuswindow "address:$addr"
              else
                hyprctl dispatch exec "${constants.paths.term} --class $APP_ID -e aerc"
              fi
            elif [[ "$XDG_CURRENT_DESKTOP" == "niri" ]] && command -v niri &> /dev/null; then
              id=$(niri msg --json windows | jq -r --arg c "$APP_ID" '.[] | select(.app_id == $c) | .id' | head -n1)
              if [[ -n "$id" ]]; then
                niri msg action focus-window --id "$id"
              else
                niri msg action spawn -- ${constants.paths.term} --class "$APP_ID" -e aerc
              fi
            else
              ${constants.paths.term} --class "$APP_ID" -e aerc
            fi
          '';
          executable = true;
        };
        ".local/bin/unsubscribe-mail".source = ../../../../aerc/scripts/unsubscribe;
        ".local/bin/aerc-nvim-pager".source = ../../../../aerc/scripts/nvim-pager.sh;
        ".w3m".source = ../../../../w3m;
      };
    };
}
