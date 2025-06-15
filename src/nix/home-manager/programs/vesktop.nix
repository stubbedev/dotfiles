{ pkgs, config, ... }: {
  programs.vesktop = {
    enable = true;
    extraArgs = [ "--no-sandbox" ];
    package = (config.lib.nixGL.wrap pkgs.vesktop);
    vencord.settings = {
      autoUpdate = true;
      autoUpdateNotification = false;
      notifyAboutUpdates = false;
      plugins = { FakeNitro.enabled = true; };
    };
  };
}
