{ self, inputs, ... }:
{
  flake.modules.homeManager.packagesCodex =
    {
      pkgs,
      lib,
      config,
      homeLib,
      ...
    }:
    lib.mkIf config.features.codex (
      let
        servers = import (self + "/lib/mcp-servers-wired.nix") {
          inherit
            self
            inputs
            pkgs
            config
            ;
        };

        # Same socket-activated proxy-mcp route Claude uses (lib/mcp-servers.nix
        # `proxied`), so codex shares the ONE browser instead of spawning its own
        # `npx chrome-devtools-mcp`. Absent when features.browsers is off.
        chrome = servers.proxied.chrome-devtools or null;

        # codex has no managed-config mechanism, and ~/.codex/config.toml is
        # user/`codex mcp add`-owned — so wire the server through `-c` overrides
        # (dotted TOML path) rather than fighting over the file.
        # ponytail: one server, one flag pair; loop over `servers.proxied` if
        # codex ever needs more than the browser.
        mcpFlags = lib.optionals (chrome != null) [
          "-c"
          ''mcp_servers.chrome-devtools.url="http://${chrome.host}:${toString chrome.port}${chrome.path}"''
        ];
      in
      {
        home.packages = [
          (homeLib.mkWrappedPackage {
            pkg = pkgs.codex;
            gfx = false;
            flags = [ "--yolo" ] ++ mcpFlags;
          })
        ];
      }
    );
}
