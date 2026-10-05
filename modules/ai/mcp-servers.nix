# MCP: notmuch is the global server, rendered into each client; every other
# server is registered per repo via .mcp.json, whose bare command
# resolves off PATH — which is all this module exists for: putting the
# binaries there. Credentials for the per-repo servers are sops-rendered
# config.json files (modules/ai/mcp-services.nix).
{ inputs, ... }:
{
  flake.modules.homeManager.mcpServers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pkg = name: inputs.${name}.packages.${system}.default;

      serverNames = [
        "atlassian-mcp"
        "jenkins-mcp"
        "sentry-mcp"
        "ds-mcp"
        "nix-mcp"
      ]
      ++ lib.optional config.features.desktop "notmuch-mcp";
    in
    {
      home.packages = map pkg serverNames;
    };
}
