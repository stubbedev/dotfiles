_: {
  flake.modules.homeManager.mcpServices =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.claudeCode {
      # Credentials only: each server reads its config from
      # ~/.config/<name>/config.json when a client spawns it as stdio. There
      # are no MCP services or ports to manage any more.
      sops.secrets = lib.listToAttrs (
        map
          (
            provider:
            lib.nameValuePair "${provider}_mcp" (
              pkgs.stubbe.secret {
                name = "${provider}-mcp.json";
                path = "${config.home.homeDirectory}/.config/${provider}-mcp/config.json";
              }
            )
          )
          [
            "atlassian"
            "jenkins"
            "sentry"
            "ds"
          ]
      );
    };
}
