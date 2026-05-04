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
      vncviewerGfx = homeLib.gfxExe "vncviewer" pkgs.tigervnc;

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
          vncviewerGfx
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
