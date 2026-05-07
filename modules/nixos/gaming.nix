_: {
  flake.modules.nixos.gaming =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Gate on host.installed so the installer ISO doesn't carry steam +
    # 32-bit graphics + lutris (saves ~hundreds of MB of squashfs).
    lib.mkIf config.host.installed {
      # programs.steam.enable wires up the Steam package, 32-bit
      # graphics support, controller udev rules, and firewall ports for
      # Remote Play / Game Sharing. Plain `pkgs.steam` in
      # environment.systemPackages skips all of that.
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
      };

      # GameMode optimises CPU governor / IO niceness while a game runs.
      # Lutris hooks into it automatically when the lib is present.
      programs.gamemode.enable = true;

      environment.systemPackages = with pkgs; [
        # MangoHud overlay (FPS/CPU/GPU). Toggle in-game with R_Shift+F12.
        mangohud
        # winetricks for hand-rolled wine prefixes; Steam's proton runtime
        # is self-contained, but wine bottles outside of Steam still use it.
        winetricks
      ];
    };
}
