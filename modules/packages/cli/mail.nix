# CLI mail and TUI helpers
_: {
  flake.modules.homeManager.packagesCliMail =
    {
      self,
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
        (rustPlatform.buildRustPackage (
          let
            # Pin the source to a content-addressed store path so the
            # derivation hash doesn't depend on the wider flake's outPath
            # (which churns whenever activation writes back into the tree
            # — zsh `.zwc` recompiles, generated completions, etc. — since
            # `path:` flakes ignore .gitignore). The filter also drops a
            # local cargo `target/` from the hash.
            src = builtins.path {
              path = self + "/src/aerc/scripts/aerc-html-filter";
              name = "aerc-html-filter-src";
              filter = path: _type: builtins.baseNameOf path != "target";
            };
          in
          {
            pname = "aerc-html-filter";
            version = "0.1.0";
            inherit src;
            cargoLock.lockFile = src + "/Cargo.lock";
            doCheck = false;
          }
        ))
      ];
    };
}
