{ self, ... }:
{
  flake.modules.homeManager.filesAtlassianMcp =
    {
      config,
      ...
    }:
    {
      # Binary-mode secret: secrets/atlassian-mcp is the raw JSON config the
      # @stubbedev/atlassian-mcp server reads at startup. sops-nix decrypts
      # and writes it verbatim. Edit with: hm secret edit atlassian-mcp
      sops.secrets.atlassian_mcp = {
        sopsFile = self + "/secrets/atlassian-mcp";
        format = "binary";
        path = "${config.home.homeDirectory}/.atlassian-mcp.json";
      };
    };
}
