_: {
  enableIf = { config, ... }: config.features.opencode;
  args =
    { config, ... }:
    {
      actionScript = ''
        ln -sfn "${config.home.homeDirectory}/.local/share/opencode/opencode-local.db" "${config.home.homeDirectory}/.local/share/opencode/opencode.db"
      '';
    };
}
