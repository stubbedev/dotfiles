_: {
  flake.modules.homeManager.programsDirenv =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.development {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        # Zsh integration is our own zcompiled `direnv hook zsh`
        # (modules/home/zsh/ → direnvInit), sourced from the store to
        # avoid a per-shell eval fork; HM's would inject a second,
        # duplicate hook after ours.
        enableZshIntegration = false;
        # Silence the "direnv: loading/export" chatter at the source —
        # direnv's own log filter drops these status lines while real
        # errors (which route through log_error) still surface. Replaces
        # the old stderr-grep wrapper. The message passed to the filter
        # has no "direnv: " prefix, so anchor on the bare verb.
        config.global.log_filter = "^(loading|export)";
      };
    };
}
