_: {
  # secrets/<provider>-mcp is the raw JSON config the
  # @stubbedev/<provider>-mcp server reads at startup. Edit any of them
  # with: hm secret edit <provider>-mcp
  flake.modules.homeManager.filesMcpSecrets =
    {
      config,
      lib,
      homeLib,
      ...
    }:
    let
      providers = [
        "atlassian"
        "jenkins"
        "sentry"
      ];
      mkSecret =
        provider:
        lib.nameValuePair "${provider}_mcp" (
          homeLib.mkBinarySecret {
            name = "${provider}-mcp";
            path = "${config.home.homeDirectory}/.${provider}-mcp.json";
          }
        );
    in
    {
      sops.secrets = lib.listToAttrs (map mkSecret providers);
    };
}
