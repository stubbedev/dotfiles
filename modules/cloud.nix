_: {
  flake.modules.nixos.cloud =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vultr-cli
        s5cmd
      ];
    };

  flake.modules.homeManager.cloud =
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [
        vultr-cli
        s5cmd
      ];

      sops.secrets.vultr = pkgs.stubbe.secret { name = "vultr"; };
      sops.templates."vultr-cli.yaml" = {
        content = "api-key: ${config.sops.placeholder.vultr}";
        path = "${config.home.homeDirectory}/.vultr-cli.yaml";
      };

      # ~/.config/gh/hosts.yml carries the GitHub CLI oauth_token. By default gh
      # stashes the token in libsecret under "Default_Keyring", which PAM does
      # NOT auto-unlock — so the token effectively vanishes on every reboot.
      # Pinning hosts.yml through sops sidesteps the keyring entirely.
      sops.secrets.gh_hosts = pkgs.stubbe.secret {
        name = "gh-hosts.yaml";
        path = "${config.home.homeDirectory}/.config/gh/hosts.yml";
      };
    };
}
