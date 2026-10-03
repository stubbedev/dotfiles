_: {
  flake.modules.homeManager.mcpClients =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.stubbe.mcp) servers;

      # The global client set is only the stdio servers that are not
      # repoScoped — notmuch on desktop hosts. Everything else (the HTTP
      # services, nix-mcp, ds) is deliberately unregistered: repos that want
      # a server list it in a .mcp.json, hitting
      # http://127.0.0.1:<port>/mcp for the services.
      clientServers = lib.mapAttrs (_: s: {
        type = "stdio";
        inherit (s) command args;
      }) (lib.filterAttrs (_: s: !(s.repoScoped or false)) servers.stdioServers);
    in
    {
      options.stubbe.mcp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Per-agent renderings of the global MCP set: `claude` and `harness` (JSON).";
      };

      config.stubbe.mcp.clients = {
        claude = clientServers;
        harness = clientServers;
      };
    };
}
