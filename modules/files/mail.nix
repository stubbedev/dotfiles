_: {
  flake.modules.homeManager.filesMail =
    {
      constants,
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file = {
        ".local/bin/open-mail" = {
          text = builtins.replaceStrings
            [ "@TERM@" ]
            [ constants.paths.term ]
            (builtins.readFile (self + "/src/_shared/scripts/open-mail"));
          executable = true;
        };
        ".local/bin/unsubscribe-mail".source = self + "/src/aerc/scripts/unsubscribe";
        ".local/bin/aerc-nvim-pager".source = self + "/src/aerc/scripts/nvim-pager.sh";
        ".w3m".source = self + "/src/w3m";
      };
    };
}
