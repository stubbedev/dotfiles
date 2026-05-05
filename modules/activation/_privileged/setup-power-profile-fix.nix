{ self, ... }:
{
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, homeLib, ... }:
    {
      promptTitle = "Installing polkit rule for CPU frequency scaling fix";
      promptBody = ''
        This allows ${config.home.username} to adjust CPU energy performance
        preferences when power profile changes, fixing the 400MHz lock issue.
      '';
      promptQuestion = "Install power profile fix polkit rule?";
      actionScript = homeLib.installPolkitRule {
        target = "/etc/polkit-1/rules.d/50-power-profile-fix.rules";
        content = homeLib.substituteFile {
          file = self + "/src/polkit/50-power-profile-fix.rules";
          vars = {
            USERNAME = config.home.username;
            HELPER_PATH = "${config.home.homeDirectory}/.stubbe/src/_shared/scripts/power.profile.helper.sh";
          };
        };
      };
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
