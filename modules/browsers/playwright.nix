# Playwright's `chrome` channel probes exactly one path on Linux:
# /opt/google/chrome/chrome. Point it at the Nix Chrome. L+ tracks store
# path drift across switches.
_: {
  flake.modules.nixos.playwrightChrome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.browsers {
      systemd.tmpfiles.rules = [
        "L+ /opt/google/chrome/chrome 0755 root root - ${pkgs.google-chrome}/bin/google-chrome-stable"
      ];
    };
}
