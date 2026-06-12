_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    {
      config,
      pkgs,
      homeLib,
      ...
    }:
    let
      # Must match modules/files/mail.nix's maildir / notmuch database path.
      maildir = "${config.home.homeDirectory}/.local/share/mail";
    in
    {
      actionScript = ''
        ${homeLib.mkLiveSymlink {
          inherit config;
          src = "aerc/stylesets";
          target = ".config/aerc/stylesets";
        }}

        # aerc reads via notmuch://, which fails with "No database found"
        # if the maildir or its .notmuch index don't exist yet. mbsync
        # also refuses to open a MaildirStore whose Path doesn't exist
        # ("Maildir error: cannot open store …") — it does not mkdir its
        # own Path. The mail-sync timer would hit the same error on every
        # tick, so bootstrap the maildir tree + an empty notmuch DB at
        # activation; aerc then opens immediately and mbsync's first run
        # has somewhere to land.
        mkdir -p "${maildir}/kontainer" "${maildir}/gmail"
        if [ ! -d "${maildir}/.notmuch" ]; then
          ${pkgs.notmuch}/bin/notmuch --config="${config.home.homeDirectory}/.notmuch-config" new --quiet || true
        fi
      '';
    };
}
