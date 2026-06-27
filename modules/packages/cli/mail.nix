# CLI mail and TUI helpers
{ inputs, ... }: {
  flake.modules.homeManager.packagesCliMail =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop (
      let system = pkgs.stdenv.hostPlatform.system;
      in {
      home.packages = with pkgs; [
        msmtp
        w3m
        pandoc
        lynx
        chafa
        catimg
        # IMAP -> local maildir mirror, paired with notmuch indexing. aerc's
        # `source=notmuch://…` reads from the indexed maildir instead of
        # talking to IMAP per message; mbsync propagates flag/tag changes
        # back. See modules/files/mail.nix for the wiring.
        isync
        notmuch
        glow
        # aerc text/html filter: parses with html5ever (kuchikiki), flattens
        # layout tables (heuristic preserves real data tables), strips
        # MSO/Word noise, then renders Markdown via htmd. Single static
        # binary — source: github:stubbedev/html-to-md.
        inputs.html-to-md.packages.${system}.default
      ];
    });
}
