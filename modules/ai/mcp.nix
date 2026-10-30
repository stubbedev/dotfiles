_: {
  flake.modules.homeManager.mcpServers =
    { lib, ... }:
    {
      options.stubbe.mcpServers = lib.mkOption {
        type = lib.types.attrsOf lib.types.raw;
        internal = true;
        default = { };
        description = "The global MCP servers every AI client registers. Per-repo servers come from each repo's .mcp.json.";
      };
    };
}
