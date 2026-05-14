{ self, ... }:
{
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "polkit rule for CPU frequency scaling fix";
      body = ''
        This allows ${config.home.username} to adjust CPU energy performance
        preferences when power profile changes, fixing the 400MHz lock issue.
      '';
      actionScript = homeLib.installPolkitRule {
        target = "/etc/polkit-1/rules.d/50-power-profile-fix.rules";
        content = homeLib.substituteFile {
          file = self + "/src/polkit/50-power-profile-fix.rules";
          vars = {
            USERNAME = config.home.username;
            # Must stay in lockstep with modules/home/scripts.nix and
            # modules/nixos/polkit.nix — see lib.nix:powerProfileHelperPath.
            HELPER_PATH = homeLib.powerProfileHelperPath;
          };
        };
      };
    };
}
