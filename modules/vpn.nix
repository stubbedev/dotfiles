# The corporate VPN: openconnect driven by four scripts per provider, with the
# gateway/credentials decrypted by sops and the passwordless pkexec rule that
# lets the status-bar toggle work without a prompt.
_: {
  flake.modules.homeManager.vpn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # connect / disconnect / status / bar for one provider, as Nix bins named
      # vpn-<provider>-<action>. `bar` is the status-widget tool (emits JSON,
      # dispatches the toggle). The provider name is baked in via
      # @PROVIDER_NAME@; runtime config is decrypted to
      # ~/.config/vpn/<provider>/.
      mkScripts =
        provider:
        map
          (
            action:
            pkgs.stubbe.scriptBin {
              name = "vpn-${provider}-${action}";
              source = "src/vpn/${provider}/${action}.sh";
              vars.PROVIDER_NAME = provider;
            }
          )
          [
            "connect"
            "disconnect"
            "status"
            "bar"
          ];
    in
    lib.mkIf config.features.vpn {
      # Two binary secrets per provider: the gateway/username config (rotates
      # rarely — `hm secret edit vpn-konform-config`) and the password (rotates
      # often — `hm secret set vpn-konform`). Both decrypt under
      # ~/.config/vpn/konform/, which the connect/bar scripts read at runtime.
      sops.secrets = {
        vpn-konform-config = pkgs.stubbe.secret {
          name = "vpn-konform-config";
          path = "${config.home.homeDirectory}/.config/vpn/konform/config";
        };
        vpn-konform = pkgs.stubbe.secret {
          name = "vpn-konform";
          path = "${config.home.homeDirectory}/.config/vpn/konform/password";
        };
      };

      home.packages = mkScripts "konform";

      # Non-NixOS half of the rule modules/polkit.nix installs on NixOS. The
      # rule is deliberately narrow: it validates the whole openconnect command
      # line (cookie on stdin only, one host, a /run/user pid-file) rather than
      # granting blanket pkexec.
      stubbe.setup.vpnPolkit = {
        privileged = true;
        title = "Installing polkit rule for VPN (passwordless pkexec)";
        body = ''
          This allows ${config.home.username} to run openconnect/pkill via pkexec
          without a password prompt.
        '';
        script = pkgs.stubbe.installPolkitRule {
          target = "/etc/polkit-1/rules.d/49-openconnect.rules";
          source = pkgs.stubbe.render "src/polkit/49-openconnect.rules" {
            USERNAME = config.home.username;
            PROFILE_DIR = config.home.profileDirectory;
          };
        };
      };
    };
}
