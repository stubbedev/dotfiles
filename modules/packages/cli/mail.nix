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
        # aerc text/html filter: parses with html5ever (kuchikiki), flattens
        # layout tables (heuristic preserves real data tables), strips
        # MSO/Word noise, then renders Markdown via htmd. Single static
        # binary — replaces the prior python+bs4+html-to-markdown pipeline.
        (rustPlatform.buildRustPackage {
          pname = "aerc-html-filter";
          version = "0.1.0";
          src = self + "/src/aerc/scripts/aerc-html-filter";
          cargoLock.lockFile = self + "/src/aerc/scripts/aerc-html-filter/Cargo.lock";
          doCheck = false;
        })
      ];
    };
}
