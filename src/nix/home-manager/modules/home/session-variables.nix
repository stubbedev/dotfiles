_: {
  flake.modules.homeManager.sessionVariables =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.sessionVariables =
        {
          # Nix configuration
          NIXPKGS_ALLOW_UNFREE = "1";
          NIXPKGS_ALLOW_INSECURE = "1";
          NIXOS_OZONE_WL = "1";

          # Editor and display
          EDITOR = lib.getExe pkgs.neovim;

          # Desktop entries (Flatpak + Nix)
          XDG_DATA_DIRS = lib.mkForce "${config.home.homeDirectory}/.local/share/flatpak/exports/share:${config.home.homeDirectory}/.nix-profile/share:/nix/var/nix/profiles/default/share:/var/lib/flatpak/exports/share:/usr/share/ubuntu:/usr/local/share:/usr/share:/var/lib/snapd/desktop:$XDG_DATA_DIRS";

          # Paging and documentation
          MANPAGER = "sh -c 'col -bx | bat -l man -p'";
          MANROFFOPT = "-c";
          PAGER = "${pkgs.more}/bin/more";

          # Node
          NODE_USE_SYSTEM_CA = "1";
          NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.cache/node/extra-ca.pem";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";

          # Go configuration
          GOROOT = "${config.home.homeDirectory}/.go";
          GOPATH = "${config.home.homeDirectory}/go";

          # Theme and custom variables
          DEPLOYER_REMOTE_USER = "abs";

          # FZF
          FZF_DEFAULT_OPTS = ''
            --color=bg+:-1,bg:-1,spinner:#f5e0dc,hl:#f38ba8
            --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
            --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
            --color=selected-bg:-1,selected-fg:#b4befe
            --color=current-fg:#cba6f7
            --multi
          '';
          FZF_CTRL_T_OPTS = ''
            --walker-skip .git,node_modules,target
            --preview '[[ -f {} ]] && bat -n --color=always {} || ls -lhA --color=always {}'
            --bind 'ctrl-/:change-preview-window(down|hidden|)'
          '';
          FZF_CTRL_R_OPTS = "";
          FZF_ALT_C_COMMAND = "";

          # Starship
          STARSHIP_CONFIG = "${config.home.homeDirectory}/.stubbe/src/starship/starship.toml";
          STARSHIP_LOG = "error";
          GTK_THEME_VARIANT = "dark";
        };
    };
}
