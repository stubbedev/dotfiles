_: {
  flake.modules.homeManager.filesLogseq =
    {
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file = {
        ".logseq/config/config.edn".source = self + "/src/logseq/config.edn";
        ".local/state/logseq/notes/logseq/custom.css".source = self + "/src/logseq/custom.css";
      };
    };
}
