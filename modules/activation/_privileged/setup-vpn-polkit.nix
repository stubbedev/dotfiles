{ self, ... }:
{
  enableIf = { config, ... }: config.features.vpn;
  args =
    { config, homeLib, ... }:
    {
      promptTitle = "Installing polkit rule for VPN (passwordless pkexec)";
      promptBody = ''
        This allows ${config.home.username} to run openconnect/pkill via pkexec
        without a password prompt.
      '';
      promptQuestion = "Install VPN polkit rule?";
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
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
