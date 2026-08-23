{
  lib,
  servers,
}:
let
  # One client-facing inventory for every MCP-capable agent. A proxied entry
  # intentionally wins over its native HTTP service with the same name (the
  # proxy adds repo gating for jenkins/sentry). A future global stdio entry wins
  # last, matching the old Claude merge order.
  clientServers =
    lib.mapAttrs (_: s: {
      transport = "http";
      url = "http://${s.host}:${toString s.port}${s.path}";
    }) (servers.httpServices // servers.proxied)
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
  # server table as a dotted config override. JSON strings/arrays are valid TOML
  # values here; inline tables need TOML's `=` separators. env_http_headers reads
  # PWD from Codex's launch environment, giving HTTP servers the same per-window
  # X-Repo-Root value as Claude.
  tomlInlineTable =
    attrs:
    "{${
      lib.concatStringsSep "," (
        lib.mapAttrsToList (key: value: "${builtins.toJSON key}=${builtins.toJSON value}") attrs
      )
    }}";
  toCodex = name: server: [
    "-c"
    (lib.escapeShellArg "mcp_servers.${name}=${
      if server.transport == "http" then
        ''{url=${builtins.toJSON server.url},env_http_headers={"X-Repo-Root"="PWD"}}''
      else
        "{command=${builtins.toJSON server.command},args=${builtins.toJSON server.args}${
          lib.optionalString (server ? env) ",env=${tomlInlineTable server.env}"
        }}"
    }")
  ];
in
{
  inherit clientServers;
  claudeServers = lib.mapAttrs toClaude clientServers;
  codexFlags = lib.concatLists (lib.mapAttrsToList toCodex clientServers);
}
