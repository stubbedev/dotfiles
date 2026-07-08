_: {
  # secrets/<provider>-mcp is the raw JSON config the <provider>-mcp server reads
  # at startup (URLs + tokens). Edit any of them with:
  #   hm secret edit <provider>-mcp
  # Decrypted to ~/.config/<provider>-mcp/config.json, which the HTTP services in
  # modules/home/mcp-proxy.nix pass via --config.
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
        # Readonly DB server (ds-mcp). Same shape: the server reads
        # ~/.config/ds-mcp/config.json (MySQL + MongoDB sources, live +
        # staging, readonly:true). Edit creds with: hm secret edit ds-mcp.
        "ds"
      ];
      mkSecret =
        provider:
        lib.nameValuePair "${provider}_mcp" (
          homeLib.mkBinarySecret {
            name = "${provider}-mcp";
            path = "${config.home.homeDirectory}/.config/${provider}-mcp/config.json";
          }
        );
    in
    {
      sops.secrets = lib.listToAttrs (map mkSecret providers);
    };
}
