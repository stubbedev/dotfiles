{ ... }: {
  programs.vesktop = {
    enable = true;
    vencord.settings = {
      autoUpdate = true;
      autoUpdateNotification = false;
      notifyAboutUpdates = false;
      plugins = { FakeNitro.enabled = true; };
    };
  };
}
