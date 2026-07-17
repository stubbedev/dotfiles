{ inputs, ... }:
{
  flake.modules.homeManager.sessionVariables =
    {
      config,
      constants,
      lib,
      pkgs,
      ...
    }:
    {
      home.sessionVariables = {
        # Cursor — single source of truth in constants.nix. Mirrored on the
        # NixOS side via modules/nixos/desktop.nix so login shells and PAM
        # see the same values. Hyprland's exec-once setcursor and
        # src/hypr/scripts/monitor.toggle.sh read these at runtime.
        XCURSOR_THEME = constants.theme.cursor;
        XCURSOR_SIZE = toString constants.theme.cursorSize;

        # Wallpaper path for the DRM-hotplug listener (monitor.toggle.sh on
        # Hyprland) to re-apply on dock. Single
        # source of truth: constants.paths.wallpaper — also templated into
        # wayle-launch's startup set (modules/home/scripts.nix).
        WALLPAPER = constants.paths.wallpaper;

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
        ROFI_SENSIBLE_TERMINAL = "${config.home.profileDirectory}/bin/alacritty";

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
        # on NixOS (modules/nixos/mkcert.nix), update-ca-certificates output
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
