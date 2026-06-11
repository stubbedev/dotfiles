_: {
  # System-wide MIME defaults written to /etc/xdg/mimeapps.list. Acts as
  # the fallback when a user has no ~/.config/mimeapps.list entry for a
  # given type — home-manager's xdg.mimeApps (modules/home/xdg/base.nix)
  # overrides these per-user.
  flake.modules.nixos.mimeDefaults =
    { lib, ... }:
    let
      # mpv is the default opener for all video formats.
      videoTypes = [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "video/mpeg"
        "video/x-flv"
        "video/ogg"
        "video/3gpp"
        "video/3gpp2"
        "video/x-ms-wmv"
        "video/x-ms-asf"
        "video/x-m4v"
        "video/mp2t"
        "video/dv"
        "video/avi"
        "application/x-matroska"
      ];
      # imv is the default opener for still images (svg left to the browser).
      imageTypes = [
        "image/jpeg"
        "image/png"
        "image/gif"
        "image/webp"
        "image/avif"
        "image/tiff"
        "image/bmp"
        "image/heif"
        "image/heic"
        "image/jxl"
        "image/x-icon"
        "image/x-portable-pixmap"
        "image/x-portable-anymap"
      ];
    in
    {
      xdg.mime.defaultApplications = {
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
        "text/html" = "firefox.desktop";
        "application/xhtml+xml" = "firefox.desktop";
      }
      // lib.genAttrs videoTypes (_: "mpv.desktop")
      // lib.genAttrs imageTypes (_: "imv.desktop");
    };
}
