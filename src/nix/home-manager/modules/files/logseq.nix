_: {
  flake.modules.homeManager.filesLogseq =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.file = {
        ".logseq/config/config.edn".source = ../../../../logseq/config.edn;
        ".local/state/logseq/notes/logseq/custom.css".source = ../../../../logseq/custom.css;
      };
    };
}
