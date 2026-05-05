_: {
  linuxOnlyHomeModules.packagesSlackWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.slack {
      # Slack ships its own chrome-sandbox under lib/slack. From /nix/store
      # it can't be SUID, so the helper aborts. Pass --disable-setuid-sandbox
      # so Chromium falls back to the userns sandbox; the matching AppArmor
      # profile is installed by setup-slack-apparmor on Ubuntu 24.04+.
      home.packages = [
        (homeLib.mkWrappedPackage {
          pkg = pkgs.slack;
          flags = [ "--disable-setuid-sandbox" ];
        })
      ];
    };
}
