_: {
  flake.modules.nixos.gaming =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.host.installed {
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
      };

      programs.gamemode.enable = true;

      environment.systemPackages = with pkgs; [
        mangohud
        winetricks
        r2modman
      ];
    };
}
