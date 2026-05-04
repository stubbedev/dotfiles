{ self, ... }:
{
  flake.modules.homeManager.filesIntelephense =
    {
      config,
      ...
    }:
    {
      # Binary-mode secret: secrets/intelephense is one opaque blob containing
      # the licence string. sops-nix decrypts and writes it verbatim to the
      # path. Edit with: hm secret edit intelephense
      sops.secrets.intelephense_license = {
        sopsFile = self + "/secrets/intelephense";
        format = "binary";
        path = "${config.home.homeDirectory}/intelephense/license.txt";
      };
    };
}
