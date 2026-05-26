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
        # Hyprland's setcap wrapper leaks CAP_SYS_NICE into children's
        # ambient set, which trips bwrap's "Unexpected capabilities but
        # not setuid" check and prevents Steam's FHS env from launching.
        # Override buildFHSEnv's bubblewrap to strip ambient caps before
        # invoking the real bwrap. Done via .override (not a wholesale
        # package replacement) so the NixOS module's own .override on
        # programs.steam.package still works.
        package = pkgs.steam.override (_prev: {
          buildFHSEnv = pkgs.buildFHSEnv.override {
            bubblewrap = pkgs.symlinkJoin {
              name = "bubblewrap-strip-ambient-caps";
              paths = [ pkgs.bubblewrap ];
              nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
              postBuild = ''
                rm $out/bin/bwrap
                makeWrapper ${pkgs.util-linux}/bin/setpriv $out/bin/bwrap \
                  --add-flags "--ambient-caps=-all" \
                  --add-flags "${pkgs.bubblewrap}/bin/bwrap"
              '';
            };
          };
        });
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
