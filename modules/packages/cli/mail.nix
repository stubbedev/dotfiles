# CLI mail and TUI helpers
{ inputs, ... }: {
  flake.modules.homeManager.packagesCliMail =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
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
        # aerc text/html filter: parses with html5ever (kuchikiki), flattens
        # layout tables (heuristic preserves real data tables), strips
        # MSO/Word noise, then renders Markdown via htmd. Single static
        # binary — replaces the prior python+bs4+html-to-markdown pipeline.
        # Source: github:stubbedev/html-to-md (flake = false, pinned in flake.lock)
        (rustPlatform.buildRustPackage {
          pname = "html-to-md";
          version = "0.1.0";
          src = inputs.html-to-md;
          cargoLock.lockFile = inputs.html-to-md + "/Cargo.lock";
          doCheck = false;
        })
      ];
    };
}
