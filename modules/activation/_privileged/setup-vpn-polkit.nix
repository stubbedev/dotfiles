{ self, ... }:
{
  enableIf = { config, ... }: config.features.vpn;
  args =
    { config, homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "polkit rule for VPN (passwordless pkexec)";
      body = ''
        This allows ${config.home.username} to run openconnect/pkill via pkexec
        without a password prompt.
      '';
      actionScript = homeLib.installPolkitRule {
        target = "/etc/polkit-1/rules.d/49-openconnect.rules";
        content = homeLib.substituteFile {
          file = self + "/src/polkit/49-openconnect.rules";
          vars = {
            USERNAME = config.home.username;
            HOME = config.home.homeDirectory;
          };
        };
      };
    };
}
