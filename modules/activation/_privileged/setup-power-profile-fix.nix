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
            # pkexec canonicalises symlinks; reference a content-addressed
            # store path so the rule matches what pkexec sees regardless of
            # where the checkout lives, AND so the path is stable across
            # rebuilds (using `self + "/..."` keys the hash on the whole
            # flake source, which changes every commit and causes the sudo
            # prompt to fire on every `hm switch`). Must stay in lockstep
            # with the script's HELPER_PATH in modules/home/scripts.nix and
            # the NixOS rule in modules/nixos/polkit.nix.
            HELPER_PATH = toString (builtins.path {
              name = "power-profile-helper";
              path = self + "/src/_shared/scripts/power.profile.helper.sh";
            });
          };
        };
      };
    };
}
