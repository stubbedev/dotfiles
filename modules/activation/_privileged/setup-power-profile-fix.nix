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
            # pkexec canonicalises symlinks; reference the flake store path
            # so the rule matches what pkexec sees regardless of where the
            # checkout lives. Must stay in lockstep with the script's
            # HELPER_PATH set in modules/home/scripts.nix.
            HELPER_PATH = toString (self + "/src/_shared/scripts/power.profile.helper.sh");
          };
        };
      };
    };
}
