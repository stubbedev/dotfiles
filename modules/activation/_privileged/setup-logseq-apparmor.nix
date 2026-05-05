_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { homeLib, ... }:
    homeLib.mkAppArmorSetup {
      appName = "Logseq";
      profileName = "nix-logseq";
      programGlob = "/nix/store/*-electron*/libexec/electron/{electron,chrome-sandbox}";
      managedBy = "home-manager logseq-apparmor v1";
    };
}
