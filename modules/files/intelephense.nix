{ self, ... }:
{
  flake.modules.homeManager.filesIntelephense =
    {
      config,
      ...
    }:
    {
      # Decrypts the license value from secrets/intelephense.yaml at
      # activation time and writes it to ~/intelephense/license.txt where
      # the intelephense LSP server reads it. Edit with:
      #   hm secret edit intelephense
      sops.secrets.intelephense_license = {
        sopsFile = self + "/secrets/intelephense.yaml";
        path = "${config.home.homeDirectory}/intelephense/license.txt";
      };
    };
}
