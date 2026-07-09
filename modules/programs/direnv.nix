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
        # Silence ALL "direnv: loading/export/…" status chatter at the
        # source. log_filter is an ALLOWLIST: logStatus prints a line only
        # if the message matches, so a never-matching regex ("$." — a char
        # after end-of-text is impossible) suppresses every status line.
        # Errors go through logError, which ignores log_filter/log_format
        # entirely (hardcoded "direnv: %s"), so real failures still surface.
        config.global.log_filter = "$.";
      };
    };
}
