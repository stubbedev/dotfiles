{ self, ... }:
{
  enableIf = { config, ... }: config.features.opencode;
  args =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      configPath = "${config.home.homeDirectory}/.config/opencode/opencode.json";

      servers = import (self + "/lib/mcp-servers.nix") {
        chromePath = "${config.home.profileDirectory}/bin/google-chrome-stable";
        firefoxPath = "${config.home.profileDirectory}/bin/firefox";
      };

      # Opencode's mcp shape: { type = "local", command = [argv...], environment? = {} }
      toOpencode = _: server:
        {
          type = "local";
          command = [ server.command ] ++ server.args;
        }
        // lib.optionalAttrs (server ? env) { environment = server.env; };

      opencodeConfig = {
        "$schema" = "https://opencode.ai/config.json";
        autoupdate = false;
        watcher.ignore = [
          "node_modules/**"
          "dist/**"
          ".git/**"
        ];
        formatter = false;
        plugin = [
          "opencode-vibeguard"
          "@franlol/opencode-md-table-formatter@latest"
        ];
        mcp = lib.mapAttrs toOpencode servers;
        instructions = [ "~/.stubbe/src/opencode/plugin/shell-strategy/INFO.md" ];
      };

      configDerivation = pkgs.writeText "opencode-config.json" (builtins.toJSON opencodeConfig);
    in
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.local/share/opencode"
        ln -sfn "${config.home.homeDirectory}/.local/share/opencode/opencode-local.db" "${config.home.homeDirectory}/.local/share/opencode/opencode.db"

        mkdir -p "$(dirname "${configPath}")"
        cp -f "${configDerivation}" "${configPath}"
      '';
    };
}
