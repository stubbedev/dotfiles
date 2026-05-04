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
        html-to-markdown
        # aerc text/html filter: flattens layout tables via BeautifulSoup
        # before handing off to html-to-markdown. Bundled as a self-contained
        # python3+bs4 binary so it doesn't shadow the system python3.
        (writers.writePython3Bin "aerc-html-filter" {
          libraries = [ python3Packages.beautifulsoup4 ];
          doCheck = false;
        } (builtins.readFile (self + "/src/aerc/scripts/html-filter.py")))
      ];
    };
}
