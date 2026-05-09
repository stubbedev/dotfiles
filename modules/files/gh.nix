_: {
  flake.modules.homeManager.filesGh =
    {
      config,
      homeLib,
      ...
    }:
    {
      # ~/.config/gh/hosts.yml carries the GitHub CLI oauth_token. By default
      # gh stashes the token in libsecret under "Default_Keyring", which is
      # NOT auto-unlocked by PAM, so the token effectively vanishes on every
      # reboot. Pinning hosts.yml through sops sidesteps the keyring entirely.
      #
      # After `gh auth login` (token rotation, scope change), re-encrypt:
      #   sops -e --input-type binary --output-type binary -i ~/.config/gh/hosts.yml \
      #     && cp ~/.config/gh/hosts.yml ~/.stubbe/secrets/gh-hosts
      # or simpler, edit in place: hm secret edit gh-hosts
      sops.secrets.gh_hosts = homeLib.mkBinarySecret {
        name = "gh-hosts";
        path = "${config.home.homeDirectory}/.config/gh/hosts.yml";
      };
    };
}
