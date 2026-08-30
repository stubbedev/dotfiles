# The per-agent projections of the MCP inventory, published as
# `config.stubbe.mcp.clients`. Claude reads a JSON block, Codex takes dotted
# `-c` overrides — same inventory, two renderings, one place.
_: {
  flake.modules.homeManager.mcpClients =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.stubbe.mcp) servers;
      # One client-facing inventory for every MCP-capable agent. A proxied entry
      # intentionally wins over its native HTTP service with the same name (the
      # proxy adds repo gating for jenkins/sentry). A future global stdio entry wins
      # last, matching the old Claude merge order.
      # `repoScoped` entries are deliberately absent here: their unit/proxy route is
      # still built, but no agent loads them globally — the repos that want them
      # name the same URL in their own .mcp.json (see modules/ai/mcp-servers.nix).
      clientServers =
        lib.mapAttrs (_: s: {
          transport = "http";
          url = "http://${s.host}:${toString s.port}${s.path}";
        }) (lib.filterAttrs (_: s: !(s.repoScoped or false)) (servers.httpServices // servers.proxied))
        // lib.mapAttrs (
          _: s:
          {
            transport = "stdio";
            inherit (s) command args;
          }
          // lib.optionalAttrs (s ? env) { inherit (s) env; }
        ) servers.global;

      # Claude expands ${PWD} in static header values at window launch.
      toClaude =
        _: server:
        if server.transport == "http" then
          {
            type = "http";
            inherit (server) url;
            headers."X-Repo-Root" = "\${PWD}";
          }
        else
          {
            type = "stdio";
            inherit (server) command args;
          }
          // lib.optionalAttrs (server ? env) { inherit (server) env; };

      # Codex has no managed-config include, so its wrapper supplies each complete
      # server table as a dotted config override. TOML inline tables are the one
      # shape `pkgs.formats.toml` cannot emit (it only writes whole documents), so
      # this is the serialiser: `{k=v,…}` with TOML's `=` separators, recursing on
      # nested attrsets. Every leaf is a string, list or bool, for which JSON and
      # TOML agree on the literal — hence toJSON for keys and scalars.
      tomlValue = v: if builtins.isAttrs v then tomlInlineTable v else builtins.toJSON v;
      # TOML bare keys are [A-Za-z0-9_-]; anything else has to be quoted, and a
      # quoted TOML key is spelled the same as a JSON string.
      tomlKey = k: if builtins.match "[A-Za-z0-9_-]+" k != null then k else builtins.toJSON k;
      tomlInlineTable =
        attrs:
        "{${
          lib.concatStringsSep "," (
            lib.mapAttrsToList (key: value: "${tomlKey key}=${tomlValue value}") attrs
          )
        }}";

      # env_http_headers reads PWD from Codex's launch environment, giving HTTP
      # servers the same per-window X-Repo-Root value as Claude.
      toCodexTable =
        server:
        if server.transport == "http" then
          {
            inherit (server) url;
            env_http_headers."X-Repo-Root" = "PWD";
          }
        else
          {
            inherit (server) command args;
          }
          // lib.optionalAttrs (server ? env) { inherit (server) env; };

      toCodex = name: server: [
        "-c"
        (lib.escapeShellArg "mcp_servers.${name}=${tomlInlineTable (toCodexTable server)}")
      ];
    in
    {
      options.stubbe.mcp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Per-agent renderings of the MCP inventory: `claude` (JSON) and `codexFlags` (argv).";
      };

      config.stubbe.mcp.clients = {
        claude = lib.mapAttrs toClaude clientServers;
        codexFlags = lib.concatLists (lib.mapAttrsToList toCodex clientServers);
      };
    };
}
