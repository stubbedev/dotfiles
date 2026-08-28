# Session variables: the environment every login shell and every graphical
# app inherits.
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
        # Cursor — single source of truth: pkgs.stubbe.theme. Mirrored on the
        # NixOS side by modules/theming.nix so login shells and PAM see the
        # same values; the compositor sets them again via hl.env because a
        # non-NixOS session manager does not source hm-session-vars.sh.
        XCURSOR_THEME = pkgs.stubbe.theme.cursor;
        XCURSOR_SIZE = toString pkgs.stubbe.theme.cursorSize;

        # Wallpaper path for the DRM-hotplug listener (monitor.toggle.sh) to
        # re-apply on dock. Single source of truth: stubbe.paths.wallpaper,
        # also templated into wayle-launch's startup set (modules/wayle.nix).
        WALLPAPER = config.stubbe.paths.wallpaper;

        # Nix configuration
        NIXPKGS_ALLOW_UNFREE = "1";
        NIXPKGS_ALLOW_INSECURE = "1";
        NIXOS_OZONE_WL = "1";

        # Pin <nixpkgs> to the flake input so nixd, `nix repl`, and any
        # impure `import <nixpkgs>` resolve to the pinned revision instead
        # of whatever the legacy NIX_PATH search points at. Crucial for
        # nixd's lib lookups (mkDefault etc.) on hosts that never had
        # `nix-channel --add nixpkgs …`. Mirrored on the NixOS side via
        # nix.nixPath so root / nixos-rebuild see the same value.
        NIX_PATH = "nixpkgs=${inputs.nixpkgs}";

        # Editor and display
        ROFI_SENSIBLE_TERMINAL = config.stubbe.paths.terminal;

        # Desktop entries (Flatpak + Nix)
        XDG_DATA_DIRS = lib.mkForce "${config.home.homeDirectory}/.local/share/flatpak/exports/share:${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/var/lib/flatpak/exports/share:/usr/share/ubuntu:/usr/local/share:/usr/share:/var/lib/snapd/desktop:$XDG_DATA_DIRS";

        # Paging and documentation
        MANPAGER = "sh -c 'col -bx | bat -l man -p'";
        MANROFFOPT = "-c";
        PAGER = "${pkgs.more}/bin/more";

        # Node
        NODE_USE_SYSTEM_CA = "1";
        NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.cache/node/extra-ca.pem";
        # Point CLI tools (curl, git, python-requests, openssl) at the OS
        # trust store, NOT a bare `pkgs.cacert` bundle. The cacert bundle
        # holds only the public root CAs; it has no way to learn about the
        # mkcert development CA, so srv-served https sites (start.local …)
        # fail with "unable to get local issuer certificate" even though the
        # system trusts mkcert. /etc/ssl/certs/ca-certificates.crt is the
        # full set *including* mkcert on both targets — security.pki.caBundle
        # on NixOS (modules/srv.nix), update-ca-certificates output
        # on a standalone-HM distro (setup-mkcert-trust.nix → mkcert -install).
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        SSL_CERT_DIR = "/etc/ssl/certs";

        # pnpm global install dir. pnpm reads this and lands binaries
        # directly under PNPM_HOME (no /bin subdir); base.nix sessionPath
        # adds the same path so the bins resolve.
        PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";

        # Silence libva (VA-API) driver-probe spam. Headless Electron
        # (Cypress) and other apps probe VA-API at startup; on this host
        # the prebuilt Electron bundles an old libva whose ABI doesn't
        # match the system intel-media-driver (missing __vaDriverInit_1_0),
        # and the 32-bit driver pulled in by hardware.graphics.enable32Bit
        # sits in the search path (wrong ELF class). Both are harmless —
        # Chromium falls back to software render — but log noisily.
        # 0 = silent, 1 = errors only, 2 = errors+info (default). Note this
        # mutes ALL libva errors system-wide, video accel only (not audio).
        LIBVA_MESSAGING_LEVEL = "0";

        # Theme and custom variables
        DEPLOYER_REMOTE_USER = "abs";

        # FZF
        # Generated from pkgs.stubbe.colors, like every other themed surface.
        # bg/bg+ are -1 (terminal default) so the picker stays transparent.
        #
        # This is a shell-word string, not a config file: `#` is not a comment
        # here, it is an argument fzf will reject. Keep the commentary out here.
        #
        # tab copies the highlighted row (field 1, so the session picker's
        # "<name>\t<label>" rows yield the name) via `clip`, then aborts, so no
        # cd / session switch fires behind the copy. It is bound here rather than
        # per-picker so it works in every fzf surface at once. That costs tab its
        # default multi-select toggle, which moves to ctrl-space. Shell
        # completion is unaffected: fzf-tab blanks FZF_DEFAULT_OPTS for its own
        # invocation unless `use-fzf-default-opts` is set to yes, and it is not
        # (modules/shell.nix), so tab there stays the completion accept key.
        FZF_DEFAULT_OPTS = ''
          --color=bg+:-1,bg:-1,spinner:${c.rosewater},hl:${c.red}
          --color=fg:${c.text},header:${c.red},info:${c.mauve},pointer:${c.rosewater}
          --color=marker:${c.lavender},fg+:${c.text},prompt:${c.mauve},hl+:${c.red}
          --color=selected-bg:-1,selected-fg:${c.lavender}
          --color=current-fg:${c.mauve}
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

        # Starship (config below, at its default XDG path)
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
