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
      # A proxied entry intentionally wins over its native HTTP service of the same
      # name: the proxy is what adds repo gating for jenkins/sentry.
      clientServers = lib.mapAttrs (_: s: {
        url = "http://${s.host}:${toString s.port}${s.path}";
      }) (lib.filterAttrs (_: s: !(s.repoScoped or false)) (servers.httpServices // servers.proxied));

      # Claude expands ${PWD} in static header values at window launch.
      toClaude = _: server: {
        type = "http";
        inherit (server) url;
        headers."X-Repo-Root" = "\${PWD}";
      };

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
      toCodexTable = server: {
        inherit (server) url;
        env_http_headers."X-Repo-Root" = "PWD";
      };

      # opencode rewrites `{env:VAR}` from its own environment while reading the
      # config file, so this header lands on the same per-window repo root as
      # Claude's ${PWD} and Codex's env_http_headers.
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
