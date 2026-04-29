_: {
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      chromeExecutable = "${config.home.homeDirectory}/.nix-profile/bin/google-chrome-stable";

      # Merge our managed keys into the existing on-disk JSON at eval time.
      # claude-code rewrites these files at runtime, so we deep-merge on top of
      # whatever is currently there rather than replacing it.
      readJson = path: if builtins.pathExists path then builtins.fromJSON (builtins.readFile path) else { };
      mkMerged =
        name: target: patch:
        pkgs.writeText name (builtins.toJSON (lib.recursiveUpdate (readJson target) patch));

      settingsTarget = "${config.home.homeDirectory}/.claude/settings.json";
      configTarget = "${config.home.homeDirectory}/.claude.json";

      settingsFile = mkMerged "claude-settings.json" settingsTarget {
        statusLine = {
          type = "command";
          command = "cship";
          refreshInterval = 5;
        };
        includeCoAuthoredBy = false;
      };

      configFile = mkMerged "claude-config.json" configTarget {
        mcpServers.chrome-devtools = {
          type = "stdio";
          command = "npx";
          args = [
            "-y"
            "chrome-devtools-mcp@latest"
            "--no-usage-statistics"
            "--executable-path"
            chromeExecutable
          ];
        };
      };

      install = source: target: ''
        mkdir -p "$(dirname "${target}")"
        install -m 0644 "${source}" "${target}"
      '';
    in
    {
      actionScript = ''
        ${install settingsFile settingsTarget}
        ${install configFile configTarget}
      '';
    };
}
