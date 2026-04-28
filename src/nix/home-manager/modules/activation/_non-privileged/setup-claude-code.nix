_: {
  enableIf = { config, ... }: config.features.claudeCode;
  args =
    {
      config,
      pkgs,
      ...
    }:
    {
      actionScript = ''
        settingsFile="${config.home.homeDirectory}/.claude/settings.json"
        mkdir -p "$(dirname "$settingsFile")"
        if [ ! -f "$settingsFile" ]; then
          printf '{}' > "$settingsFile"
        fi
        tmp=$(${pkgs.jq}/bin/jq '. + {"statusLine": {"type": "command", "command": "cship", "refreshInterval": 5}, "includeCoAuthoredBy": false}' "$settingsFile")
        printf '%s\n' "$tmp" > "$settingsFile"
      '';
    };
}
