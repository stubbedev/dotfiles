# System services and utilities
_: {
  linuxOnlyHomeModules.packagesSystem =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # nixGL-wrapped alacritty (name preserved). The systemd user service
      # `alacritty-daemon` (modules/home/systemd.nix) runs `--daemon` from this
      # same derivation; the thin client below attaches new windows to it over
      # the shared IPC socket. Keep homeLib.alacrittySocket in sync with the
      # unit's --socket path.
      alacrittyGfx = homeLib.gfx pkgs.alacritty;

      # `alacritty` on PATH: attach a window to the running daemon so every
      # terminal shares one process. Single-instance lifecycle is owned by the
      # systemd unit, so this is a thin client — no spawn/poll race. Falls back
      # to a standalone window if the daemon socket isn't up yet (e.g. an early
      # login before the unit reaches its target). Control/query subcommands
      # pass straight through.
      alacrittyClient = pkgs.writeShellScriptBin "alacritty" ''
        real="${alacrittyGfx}/bin/alacritty"
        socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/alacritty.sock"

        case "''${1:-}" in
          --daemon|msg|--help|-h|--version|-V)
            exec "$real" "$@"
            ;;
        esac

        if "$real" msg --socket "$socket" create-window "$@" >/dev/null 2>&1; then
          exit 0
        fi
        exec "$real" "$@"
      '';
      # symlinkJoin the client (first-wins → shadows upstream bin/alacritty)
      # with upstream alacritty for Alacritty.desktop + icons. writeShellScriptBin
      # alone emits only bin/, so without this the desktop entry is absent on both
      # targets and alacritty never shows in rofi. The .desktop's Exec=alacritty
      # resolves to the client on PATH.
      alacrittyWrapped = pkgs.symlinkJoin {
        name = "alacritty-${pkgs.alacritty.version}";
        paths = [
          alacrittyClient
          pkgs.alacritty
        ];
        meta = pkgs.alacritty.meta // {
          mainProgram = "alacritty";
          # symlinkJoin yields a single `out` (terminfo merged in); inheriting
          # alacritty's multi-output outputsToInstall would make buildEnv fail
          # on the missing output. Same fix as lib.nix mkWrappedPackage.
          outputsToInstall = [ "out" ];
        };
      };

      # ZenNotes: keyboard-first local Markdown notes (Electron). Not in
      # nixpkgs. Per request this tracks the LATEST upstream release instead
      # of a pinned version: we read GitHub's "latest release" API at eval
      # time and fetch whatever linux AppImage it points at. Both the API
      # read and the AppImage download are unpinned `builtins.fetchurl`
      # calls, so this eval is IMPURE — `nixos-rebuild`/`home-manager switch`
      # must be run with `--impure`, and `nix flake check` will reject it.
      #
      # The AppImage carries three things we expose:
      #   * the GUI (`zennotes`)            — FHS-wrapped via appimageTools,
      #     gfx-wrapped (nixGL on non-NixOS) and given its .desktop + icons
      #     so it shows up in rofi.
      #   * the `zen` CLI                    — a POSIX wrapper that runs the
      #     bundled resources/cli.js through the packaged Electron as Node
      #     (ELECTRON_RUN_AS_NODE=1). We re-implement that wrapper here so it
      #     targets the Nix-wrapped Electron and the cli.js in the extracted
      #     store path.
      #   * the MCP stdio server (`zen mcp`) — same cli.js, registered for
      #     Claude Code in lib/mcp-servers.nix as `zennotes-mcp`.
      #
      # CLI and MCP resolve the vault from ~/.config/ZenNotes (shared with the
      # GUI) and $ZENNOTES_VAULT — never from cwd — so we `cd "$HOME"` before
      # exec: the FHS/bwrap wrapper aborts if it can't chdir into the caller's
      # cwd (e.g. a repo under /etc that the sandbox doesn't bind-mount).
      zennotes =
        let
          pname = "zennotes";
          release = builtins.fromJSON (
            builtins.readFile (
              builtins.fetchurl "https://api.github.com/repos/ZenNotes/zennotes/releases/latest"
            )
          );
          version = lib.removePrefix "v" release.tag_name;
          appimage = lib.findFirst (
            a: lib.hasSuffix "-linux-x86_64.AppImage" a.name
          ) (throw "zennotes: no linux-x86_64 AppImage asset in latest release") release.assets;
          src = builtins.fetchurl appimage.browser_download_url;
          contents = pkgs.appimageTools.extractType2 { inherit pname version src; };

          gui = pkgs.appimageTools.wrapType2 {
            inherit pname version src;
            extraInstallCommands = ''
              install -Dm444 ${contents}/ZenNotes.desktop $out/share/applications/zennotes.desktop
              substituteInPlace $out/share/applications/zennotes.desktop \
                --replace-fail 'Exec=AppRun' 'Exec=zennotes'
              cp -r ${contents}/usr/share/icons $out/share/icons
            '';
            meta = {
              description = "Keyboard-first local Markdown notes app";
              homepage = "https://zennotes.org";
              mainProgram = "zennotes";
              platforms = [ "x86_64-linux" ];
            };
          };

          # `zen` CLI + `zen mcp` stdio server. Drives the bundled cli.js
          # through the GUI's Electron binary run as Node. No GPU, so it
          # bypasses gfx/nixGL and calls the FHS-wrapped Electron directly.
          zenCli = pkgs.writeShellScriptBin "zen" ''
            cd "$HOME" || exit 1
            export ELECTRON_RUN_AS_NODE=1
            exec ${gui}/bin/zennotes ${contents}/resources/cli.js "$@"
          '';
        in
        homeLib.mkWrappedPackage {
          pkg = gui;
          extraPaths = [ zenCli ];
          mainProgram = "zennotes";
        };
    in
    lib.mkIf config.features.desktop {
      home.packages = with pkgs; [
        # Terminal emulator (GPU accelerated)
        alacrittyWrapped

        # Network management (GUI applets)
        networkmanagerapplet
        networkmanager-openconnect

        # Bluetooth (GUI)
        blueman

        # Monitor Brightness (CLI tools)
        brightnessctl
        ddcutil

        # Clipboard managers (CLI/daemon)
        clipman
        cliphist

        # Mail (TUI, no GPU needed)
        mailutils
        aerc
        khard
        vdirsyncer

        # Keyring management (for automatic password management)
        # Note: Uses system-installed GNOME Keyring and KDE Wallet from Fedora
        libsecret # Provides secret-tool command

        # Cursor and icon themes
        vimix-cursors
        vimix-icon-theme

        util-linux

        # file manager
        yazi
        pcmanfm

        # Note-taking / knowledge base. GUI (zennotes) + `zen` CLI + the
        # `zen mcp` server registered in lib/mcp-servers.nix.
        zennotes
      ];
    };
}
