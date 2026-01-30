{ ... }:
{
  flake.modules.homeManager.files = { constants, vpnScripts, ... }:
    {
      home.file = {
        ".zshrc".text = ''
          if [[ -f "${constants.paths.zsh}/init" ]]; then
            source ${constants.paths.zsh}/init
          fi
        '';
        ".ideavimrc".source = ../../../../ideavim/ideavimrc;
        ".tmux.conf".source = ../../../../tmux/tmux.conf;

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
        ".local/bin/konform-vpn-waybar" = {
          source = ../../../../vpn/konform/waybar.sh;
          executable = true;
        };
        ".local/bin/unsubscribe-mail".source = ../../../../aerc/scripts/unsubscribe;

        ".w3m".source = ../../../../w3m;
      } // vpnScripts;
    };
}
