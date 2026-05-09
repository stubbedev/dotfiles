_: {
  flake.modules.homeManager.filesNpm =
    {
      config,
      homeLib,
      ...
    }:
    {
      # ~/.npmrc holds npm's auth token in plaintext (//registry.npmjs.org/:_authToken=...).
      # Encrypting it via sops makes the login survive rebuilds. After
      # `npm login` writes a fresh token, re-encrypt with:
      #   hm secret edit npmrc
      # or:
      #   cp ~/.npmrc ~/.stubbe/secrets/npmrc \
      #     && sops -e --input-type binary --output-type binary -i ~/.stubbe/secrets/npmrc
      sops.secrets.npmrc = homeLib.mkBinarySecret {
        name = "npmrc";
        path = "${config.home.homeDirectory}/.npmrc";
      };
    };
}
