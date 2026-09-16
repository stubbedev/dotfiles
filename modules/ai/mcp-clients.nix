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

      # `type` is mandatory here -- harness's schema defaults it to "stdio", so a
      # url-only entry is parsed as a command. Header values go through harness's
      # embedded shell, hence the bare $PWD. The 15s default connect timeout is
      # too tight for a cold socket-activated mcp-proxy (TimeoutStartSec=120).
      toHarness = _: server: {
        type = "http";
        inherit (server) url;
        headers."X-Repo-Root" = "$PWD";
        timeout = 120;
      };
    in
    {
      options.stubbe.mcp.clients = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "Per-agent renderings of the MCP inventory: `claude` and `harness` (JSON).";
      };

      config.stubbe.mcp.clients = {
        claude = lib.mapAttrs toClaude clientServers;
        harness = lib.mapAttrs toHarness clientServers;
      };
    };
}
