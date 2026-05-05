_: {
  enableIf = { config, ... }: config.features.slack;
  args =
    { homeLib, ... }:
    {
      preCheck = ''
        PATH="/sbin:/usr/sbin:$PATH"
        if ! command -v apparmor_status >/dev/null 2>&1; then
          exit 0
        fi
      '';
      promptTitle = "Installing AppArmor profile for Nix-installed Slack";
      promptBody = ''
        Ubuntu 24.04 restricts unprivileged user namespaces (required by
        Chromium-based sandboxes) to binaries with a matching AppArmor
        profile. Nix-store paths aren't covered by Ubuntu's stock profiles,
        so Slack aborts on launch with "No usable sandbox!".

        This installs an AppArmor profile that whitelists the Nix-store
        Slack binary (and its sandbox helper) for unprivileged userns.
      '';
      promptQuestion = "Install AppArmor profile for Nix Slack?";
      actionScript = homeLib.installApparmorProfile {
        name = "nix-slack";
        content = ''
          # managed-by: home-manager slack-apparmor v1
          abi <abi/4.0>,
          include <tunables/global>
          profile nix-slack /nix/store/*/lib/slack/{slack,chrome-sandbox} flags=(unconfined) {
            userns,
            @{exec_path} mr,
            include if exists <local/nix-slack>
          }
        '';
      };
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
