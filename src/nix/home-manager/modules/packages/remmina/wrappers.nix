_: {
  flake.modules.homeManager.packagesRemminaWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      remminaGfx = homeLib.gfxName "remmina" pkgs.remmina;
      remminaFileWrapperGfx = homeLib.gfxExe "remmina-file-wrapper" pkgs.remmina;

      # Upstream's org.remmina.Remmina.desktop bakes absolute /nix/store
      # paths into Exec=, so launching from the menu would bypass the
      # nixGL wrapper. Provide a replacement whose Exec= uses the bare
      # command name; symlinkJoin first-wins ensures it shadows upstream's.
      remminaDesktop = pkgs.makeDesktopItem {
        name = "org.remmina.Remmina";
        desktopName = "Remmina";
        genericName = "Remote Desktop Client";
        comment = "Connect to remote desktops via RDP, VNC, SPICE, NX, XDMCP, SSH";
        exec = "remmina";
        icon = "org.remmina.Remmina";
        type = "Application";
        categories = [ "GTK" "Network" "RemoteAccess" ];
        mimeTypes = [
          "application/x-remmina"
          "x-scheme-handler/rdp"
          "x-scheme-handler/spice"
          "x-scheme-handler/vnc"
          "x-scheme-handler/remmina"
        ];
        startupNotify = true;
        terminal = false;
        actions = {
          new = {
            name = "Create a New Connection Profile";
            exec = "remmina --new";
          };
          kiosk = {
            name = "Start Remmina in Kiosk mode";
            exec = "remmina --kiosk";
          };
          minimized = {
            name = "Start Remmina Minimized";
            exec = "remmina --icon";
          };
        };
      };

      remmina-package = pkgs.symlinkJoin {
        name = "remmina-${pkgs.remmina.version}";
        paths = [
          remminaGfx
          remminaFileWrapperGfx
          remminaDesktop
          pkgs.remmina
        ];
        meta = pkgs.remmina.meta // {
          mainProgram = "remmina";
        };
      };
    in
    lib.mkIf config.features.desktop {
      home.packages = [ remmina-package ];
    };
}
