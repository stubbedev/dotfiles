# Slack. Two things the Nix build needs that the distro package does not.
_: {
  flake.modules.homeManager.slack =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.slack {
      # Slack ships its own chrome-sandbox under lib/slack. From /nix/store it
      # cannot be SUID, so the helper aborts — pass --disable-setuid-sandbox so
      # Chromium falls back to the userns sandbox instead.
      home.packages = [
        (config.stubbe.gfx.bundle {
          pkg = pkgs.slack;
          flags = [ "--disable-setuid-sandbox" ];
        })
      ];

      # …and the userns sandbox in turn needs an AppArmor profile on Ubuntu
      # 24.04+, which is what the fallback above depends on.
      stubbe.setup.slackApparmor = pkgs.stubbe.apparmorSetup {
        appName = "Slack";
        profileName = "nix-slack";
        programGlob = "/nix/store/*/lib/slack/{slack,chrome-sandbox}";
      };
    };
}
