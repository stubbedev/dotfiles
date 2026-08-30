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

      # vultr-cli reads its API key from ~/.vultr-cli.yaml (the viper default).
      # secrets/vultr holds only the raw key, so a sops template wraps it in the
      # `api-key:` YAML the CLI expects and renders the file at activation. The
      # decrypted key never lands in the world-readable store — sops renders it
      # under /run and symlinks ~/.vultr-cli.yaml there.
      # After rotating the key in the Vultr portal: hm secret edit vultr
      sops.secrets.vultr = pkgs.stubbe.secret { name = "vultr"; };
      sops.templates."vultr-cli.yaml" = {
        content = "api-key: ${config.sops.placeholder.vultr}";
        path = "${config.home.homeDirectory}/.vultr-cli.yaml";
      };

      # ~/.config/gh/hosts.yml carries the GitHub CLI oauth_token. By default gh
      # stashes the token in libsecret under "Default_Keyring", which PAM does
      # NOT auto-unlock — so the token effectively vanishes on every reboot.
      # Pinning hosts.yml through sops sidesteps the keyring entirely.
      # After `gh auth login` (token rotation, scope change):
      #   hm secret edit gh-hosts
      sops.secrets.gh_hosts = pkgs.stubbe.secret {
        name = "gh-hosts";
        path = "${config.home.homeDirectory}/.config/gh/hosts.yml";
      };
    };
}
