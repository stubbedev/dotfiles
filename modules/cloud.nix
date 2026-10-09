_: {
  flake.modules.homeManager.cloud =
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [ hcloud ];

      # The secret holds the raw token with no trailing newline: it lands inside
      # a quoted TOML string, so a newline would break the parse.
      sops.secrets.hetzner = pkgs.stubbe.secret { name = "hetzner"; };
      sops.templates."hcloud-cli.toml" = {
        content = ''
          active_context = "default"

          [[contexts]]
            name = "default"
            token = "${config.sops.placeholder.hetzner}"
        '';
        path = "${config.xdg.configHome}/hcloud/cli.toml";
      };

      sops.secrets.godaddy = pkgs.stubbe.secret { name = "godaddy"; };
      # ~/.config/gh/hosts.yml carries the GitHub CLI oauth_token. By default gh
      # stashes the token in libsecret under "Default_Keyring", which PAM does
      # NOT auto-unlock — so the token effectively vanishes on every reboot.
      # Pinning hosts.yml through sops sidesteps the keyring entirely. It reuses
      # the github-token secret nix's access-tokens already read (see nix.nix),
      # so one token rotation covers both.
      sops.secrets.github-token = pkgs.stubbe.secret { name = "github-token"; };
      sops.templates."gh-hosts.yml" = {
        content = ''
          github.com:
              git_protocol: ssh
              users:
                  stubbedev:
                      oauth_token: ${config.sops.placeholder.github-token}
              user: stubbedev
              oauth_token: ${config.sops.placeholder.github-token}
        '';
        path = "${config.xdg.configHome}/gh/hosts.yml";
      };
    };
}
