_: {
  flake.modules.homeManager.packagesTigervncWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # vncviewer is FLTK, not GTK — it can't read the GTK theme, but
      # FLTK accepts -scheme/-fg/-bg/-bg2 and Fl::args() consumes them
      # before app args. Match Catppuccin Mocha (see src/hypr/theme.conf):
      #   base #1e1e2e, text #cdd6f4, surface0 #313244.
      # makeWrapper --add-flags prepends, so user-supplied flags override.
      vncviewerGfx = homeLib.gfxExe "vncviewer" pkgs.tigervnc;
      vncviewerThemed =
        pkgs.runCommand "vncviewer-themed"
          { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            makeWrapper ${vncviewerGfx}/bin/vncviewer $out/bin/vncviewer \
              --add-flags "-scheme gtk+ -bg '#1e1e2e' -fg '#cdd6f4' -bg2 '#313244'"
          '';

      # Upstream's vncviewer.desktop bakes an absolute /nix/store path
      # into Exec=, so launching from the menu would skip the nixGL
      # wrapper. Replace it with a desktop entry whose Exec= is the bare
      # command name; symlinkJoin first-wins shadows upstream's file.
      vncviewerDesktop = pkgs.makeDesktopItem {
        name = "vncviewer";
        desktopName = "TigerVNC Viewer";
        genericName = "Remote desktop viewer";
        comment = "Connect to VNC server and display remote desktop";
        exec = "vncviewer";
        icon = "tigervnc";
        type = "Application";
        terminal = false;
        startupWMClass = "vncviewer";
        categories = [ "Network" "RemoteAccess" ];
        mimeTypes = [
          "application/x-vnc"
          "x-scheme-handler/vnc"
        ];
      };

      tigervnc-package = pkgs.symlinkJoin {
        name = "tigervnc-${pkgs.tigervnc.version}";
        paths = [
          vncviewerThemed
          vncviewerDesktop
          pkgs.tigervnc
        ];
        meta = pkgs.tigervnc.meta // {
          mainProgram = "vncviewer";
        };
      };
    in
    lib.mkIf config.features.desktop {
      home.packages = [ tigervnc-package ];
    };
}
