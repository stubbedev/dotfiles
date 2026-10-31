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

      onAndroid = config.host.platform == "android";
      androidRuntimeDir = "/tmp/runtime-${config.home.username}";

      # Only a distro keeps a trust store at /etc/ssl. nix-on-droid generates
      # /etc from the store with no certificates in it, so Android points at
      # nixpkgs' bundle. On a distro the OS store wins deliberately: it is the
      # only one srv's mkcert CA can be added to.
      tls =
        if onAndroid then
          {
            dir = "${pkgs.cacert}/etc/ssl/certs";
            file = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          }
        else
          {
            dir = "/etc/ssl/certs";
            file = "/etc/ssl/certs/ca-certificates.crt";
          };

      onDistro = config.host.platform == "linux";
      dataDirs =
        lib.optional onDistro "${config.xdg.dataHome}/flatpak/exports/share"
        ++ [
          "${config.home.profileDirectory}/share"
          "/nix/var/nix/profiles/default/share"
        ]
        ++ lib.optionals onDistro [
          "/var/lib/flatpak/exports/share"
          "/usr/share/ubuntu"
          "/usr/local/share"
          "/usr/share"
          "/var/lib/snapd/desktop"
        ];
    in
    {
      home.activation.androidRuntimeDir = lib.mkIf onAndroid (
        lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          export XDG_RUNTIME_DIR=${lib.escapeShellArg androidRuntimeDir}
          mkdir -p -m 0700 "$XDG_RUNTIME_DIR"
        ''
      );

      home.sessionVariables = {
        XDG_RUNTIME_DIR = lib.mkIf onAndroid androidRuntimeDir;
        NIXPKGS_ALLOW_UNFREE = "1";
        NIXPKGS_ALLOW_INSECURE = "1";

        # Without this nixd's lib lookups fail on any host that never ran
        # `nix-channel --add nixpkgs`.
        NIX_PATH = "nixpkgs=${inputs.nixpkgs}";

        XDG_DATA_DIRS = lib.mkForce "${lib.concatStringsSep ":" dataDirs}:$XDG_DATA_DIRS";

        MANPAGER = "sh -c '${lib.getExe' pkgs.util-linux "col"} -bx | ${lib.getExe pkgs.bat} -l man -p'";
        MANROFFOPT = "-c";
        PAGER = "${pkgs.more}/bin/more";

        NODE_USE_SYSTEM_CA = "1";
        # The OS trust store, not `pkgs.cacert`: that bundle holds only public
        # roots and cannot learn the mkcert CA, so srv-served https sites fail
        # with "unable to get local issuer certificate".
        SSL_CERT_FILE = tls.file;
        SSL_CERT_DIR = tls.dir;

        # Silences harmless but noisy VA-API probe failures (Electron bundles an
        # old libva; the 32-bit driver is the wrong ELF class). Mutes ALL libva
        # errors, so raise it when debugging video acceleration.
        LIBVA_MESSAGING_LEVEL = lib.mkIf config.features.desktop "0";

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
        GTK_THEME_VARIANT = lib.mkIf config.features.theming "dark";
      };

      xdg.configFile."starship.toml".source = pkgs.stubbe.gen.toml "starship.toml" {
        command_timeout = 100;
        nix_shell.symbol = " ";
      };
    };
}
