_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
        # Default graph dir at ~/.local/state/logseq/notes/. Logseq creates
        # journals/ and pages/ on first open, but pre-creating them means the
        # graph is openable without the app having to bootstrap it.
        mkdir -p "${config.home.homeDirectory}/.local/state/logseq/notes/journals"
        mkdir -p "${config.home.homeDirectory}/.local/state/logseq/notes/pages"

        # Electron-side toggles. Logseq rewrites this file when the user
        # changes the corresponding settings in the UI, so we overwrite it
        # the same way setup-btop.nix manages btop.conf.
        mkdir -p "${config.home.homeDirectory}/.config/Logseq"
        cat > "${config.home.homeDirectory}/.config/Logseq/configs.edn" <<'EOF'
        {:window/native-titlebar? true, :spell-check true}
        EOF
      '';
    };
}
