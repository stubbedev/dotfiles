_: {
  # System-wide MIME defaults written to /etc/xdg/mimeapps.list. Acts as
  # the fallback when a user has no ~/.config/mimeapps.list entry for a
  # given type — home-manager's xdg.mimeApps (modules/home/xdg/base.nix)
  # overrides these per-user.
  flake.modules.nixos.mimeDefaults = _: {
    xdg.mime.defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";
    };
  };
}
