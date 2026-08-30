_: {
  flake.modules.homeManager.mcpClients =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.stubbe.mcp) servers;
      # A proxied entry intentionally wins over its native HTTP service of the same
      # name: the proxy is what adds repo gating for jenkins/sentry.
      clientServers = lib.mapAttrs (_: s: {
        url = "http://${s.host}:${toString s.port}${s.path}";
      }) (lib.filterAttrs (_: s: !(s.repoScoped or false)) (servers.httpServices // servers.proxied));

      toClaude = _: server: {
        type = "http";
        inherit (server) url;
        headers."X-Repo-Root" = "\${PWD}";
      };

      # TOML inline tables are the one shape pkgs.formats.toml cannot emit, so
      # Codex's dotted `-c` overrides need this serialiser.
      tomlValue = v: if builtins.isAttrs v then tomlInlineTable v else builtins.toJSON v;
      tomlKey = k: if builtins.match "[A-Za-z0-9_-]+" k != null then k else builtins.toJSON k;
      tomlInlineTable =
        attrs:
        "{${
          lib.concatStringsSep "," (
            lib.mapAttrsToList (key: value: "${tomlKey key}=${tomlValue value}") attrs
          )
        }}";

      toCodexTable = server: {
        inherit (server) url;
        env_http_headers."X-Repo-Root" = "PWD";
      };

      toOpencode = _: server: {
        type = "remote";
        inherit (server) url;
        headers."X-Repo-Root" = "{env:PWD}";
      };

      toCodex = name: server: [
        "-c"
        (lib.escapeShellArg "mcp_servers.${name}=${tomlInlineTable (toCodexTable server)}")
      ];
    in
    {
      options.stubbe.mcp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Per-agent renderings of the MCP inventory: `claude` and `opencode` (JSON) and `codexFlags` (argv).";
      };

      config.stubbe.mcp.clients = {
        claude = lib.mapAttrs toClaude clientServers;
        opencode = lib.mapAttrs toOpencode clientServers;
        codexFlags = lib.concatLists (lib.mapAttrsToList toCodex clientServers);
      };
    };
}
