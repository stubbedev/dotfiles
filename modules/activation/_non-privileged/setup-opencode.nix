_: {
  enableIf = { config, ... }: config.features.opencode;
  args =
    { config, ... }:
    {
      actionScript = ''
        if [ ! -f "${config.home.homeDirectory}/.local/share/opencode/opencode.db" ]; then
          ln -s "${config.home.homeDirectory}/.local/share/opencode/opencode-local.db" "${config.home.homeDirectory}/.local/share/opencode/opencode.db" 2>&1 >/dev/null
        fi
      '';
    };
}
