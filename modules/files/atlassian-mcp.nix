_: {
  flake.modules.homeManager.filesAtlassianMcp =
    {
      config,
      homeLib,
      ...
    }:
    {
      # secrets/atlassian-mcp is the raw JSON config the @stubbedev/atlassian-mcp
      # server reads at startup. Edit with: hm secret edit atlassian-mcp
      sops.secrets.atlassian_mcp = homeLib.mkBinarySecret {
        name = "atlassian-mcp";
        path = "${config.home.homeDirectory}/.atlassian-mcp.json";
      };
    };
}
