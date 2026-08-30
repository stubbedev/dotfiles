{ inputs, ... }:
{
  flake.modules.homeManager.session =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      c = pkgs.stubbe.withHash;
    in
    {
      home.sessionVariables = {
        # Set again by the compositor via hl.env: a non-NixOS session manager
        # never sources hm-session-vars.sh.
        XCURSOR_THEME = pkgs.stubbe.theme.cursor;
        XCURSOR_SIZE = toString pkgs.stubbe.theme.cursorSize;

        WALLPAPER = config.stubbe.paths.wallpaper;

        NIXPKGS_ALLOW_UNFREE = "1";
        NIXPKGS_ALLOW_INSECURE = "1";
        NIXOS_OZONE_WL = "1";

        # Without this nixd's lib lookups fail on any host that never ran
        # `nix-channel --add nixpkgs`.
        NIX_PATH = "nixpkgs=${inputs.nixpkgs}";

        ROFI_SENSIBLE_TERMINAL = config.stubbe.paths.terminal;

        XDG_DATA_DIRS = lib.mkForce "${config.home.homeDirectory}/.local/share/flatpak/exports/share:${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/var/lib/flatpak/exports/share:/usr/share/ubuntu:/usr/local/share:/usr/share:/var/lib/snapd/desktop:$XDG_DATA_DIRS";

        MANPAGER = "sh -c 'col -bx | bat -l man -p'";
        MANROFFOPT = "-c";
        PAGER = "${pkgs.more}/bin/more";

        NODE_USE_SYSTEM_CA = "1";
        NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.cache/node/extra-ca.pem";
        # The OS trust store, not `pkgs.cacert`: that bundle holds only public
        # roots and cannot learn the mkcert CA, so srv-served https sites fail
        # with "unable to get local issuer certificate".
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        SSL_CERT_DIR = "/etc/ssl/certs";

        # pnpm lands binaries directly here, with no /bin subdir.
        PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";

        # Silences harmless but noisy VA-API probe failures (Electron bundles an
        # old libva; the 32-bit driver is the wrong ELF class). Mutes ALL libva
        # errors, so raise it when debugging video acceleration.
        LIBVA_MESSAGING_LEVEL = "0";

        DEPLOYER_REMOTE_USER = "abs";

        # A shell-word string, not a config file: `#` is an argument fzf rejects,
        # not a comment.
        # Binding tab here costs it the default multi-select toggle, which moves
        # to ctrl-space. Shell completion is unaffected: fzf-tab blanks
        # FZF_DEFAULT_OPTS for its own invocation.
        FZF_DEFAULT_OPTS = ''
          --color=${
            lib.concatStringsSep "," (
              lib.mapAttrsToList (role: colour: "${role}:${colour}") {
                bg = "-1";
                "bg+" = "-1";
                fg = c.text;
                "fg+" = c.text;
                hl = c.red;
                "hl+" = c.red;
                header = c.red;
                info = c.mauve;
                marker = c.lavender;
                pointer = c.rosewater;
                prompt = c.mauve;
                spinner = c.rosewater;
                "selected-bg" = "-1";
                "selected-fg" = c.lavender;
                "current-fg" = c.mauve;
              }
            )
          }
          --multi
          --bind 'tab:execute-silent(printf %s {} | cut -f1 | clip)+abort'
          --bind 'ctrl-space:toggle'
        '';
        FZF_CTRL_T_OPTS = ''
          --walker-skip .git,node_modules,target
          --preview '[[ -f {} ]] && bat -n --color=always {} || ls -lhA --color=always {}'
          --bind 'ctrl-/:change-preview-window(down|hidden|)'
        '';
        FZF_CTRL_R_OPTS = "";
        FZF_ALT_C_COMMAND = "";

        STARSHIP_LOG = "error";
        GTK_THEME_VARIANT = "dark";
      };

      xdg.configFile."starship.toml".source = (pkgs.formats.toml { }).generate "starship.toml" {
        command_timeout = 100;

        format = "\${custom.vpn}$all";

        custom.vpn = {
          when = ''ls -A $HOME | grep -q ".vpn_active-*"'';
          style = "green";
          format = "[\\[vpn\\] ]($style)";
        };
      };
    };
}
