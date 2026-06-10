{ self, ... }:
{
  flake.modules.homeManager.filesVultr =
    { config, ... }:
    {
      # vultr-cli reads its API key from ~/.vultr-cli.yaml (viper default).
      # secrets/vultr holds only the raw key (binary mode), so a sops
      # template wraps it in the `api-key:` YAML the CLI expects and
      # renders the file at activation. The decrypted key never lands in
      # the world-readable nix store — sops renders it under /run and
      # symlinks ~/.vultr-cli.yaml there.
      #
      # After rotating the key in the Vultr portal, re-encrypt:
      #   hm secret edit vultr
      sops.secrets.vultr = {
        sopsFile = self + "/secrets/vultr";
        format = "binary";
      };

      sops.templates."vultr-cli.yaml" = {
        content = "api-key: ${config.sops.placeholder.vultr}";
        path = "${config.home.homeDirectory}/.vultr-cli.yaml";
      };
    };
}
