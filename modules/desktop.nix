{ inputs, lib, ... }:
let
  browserDesktopIds = {
    firefox = "firefox.desktop";
    chrome = "com.google.Chrome.desktop";
  };
  videoPlayer = "mpv.desktop";
  imageViewer = "imv.desktop";
  lysViewer = "dev.stubbe.lys.viewer.desktop";
  fileManager = "dev.stubbe.lys.files.desktop";

  desktopEntryMimeTypes =
    path:
    let
      line = lib.findFirst (lib.hasPrefix "MimeType=") (throw "${path} declares no MimeType") (
        lib.splitString "\n" (builtins.readFile path)
      );
    in
    lib.filter (t: t != "") (lib.splitString ";" (lib.removePrefix "MimeType=" line));

  lysViewerHandlers =
    lib.genAttrs (desktopEntryMimeTypes "${inputs.lys}/viewer/resources/${lysViewer}")
      (_: lysViewer);

  browserHandlers =
    browser:
    lib.genAttrs [
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
      "text/html"
      "application/xhtml+xml"
    ] (_: browser);

  mimeDefaults =
    browser:
    let
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
    browserHandlers browser
    // lib.genAttrs videoTypes (_: videoPlayer)
    // lib.genAttrs imageTypes (_: imageViewer)
    // lysViewerHandlers;
in
{
  flake.modules.nixos.desktop =
    { config, ... }:
    {
      services.dbus.implementation = "broker";

      documentation.nixos.enable = false;

      xdg.mime.defaultApplications = mimeDefaults browserDesktopIds.${config.host.browser};
    };

  flake.modules.homeManager.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.desktop {
      home.packages =
        with pkgs;
        [
          networkmanager-openconnect

          solaar

          ddcutil

          util-linux
          xdg-utils

          lys-files
          lys-viewer
        ]
        ++ lib.optionals config.features.slack [
          (pkgs.stubbe.wrapPackage {
            pkg = pkgs.slack;
            flags = [ "--disable-setuid-sandbox" ];
          })
        ];

      xdg.mimeApps = {
        enable = true;
        # Glob keys expand against shared-mime-info at eval time; exact keys
        # would keep precedence over a glob match. The NixOS half above keeps
        # the explicit list: xdg.mime has no glob support.
        defaultApplications =
          browserHandlers browserDesktopIds.${config.host.browser}
          // {
            "inode/directory" = fileManager;
            "x-scheme-handler/file" = fileManager;
            "video/*" = videoPlayer;
            "image/*" = imageViewer;
          }
          // lysViewerHandlers;
      };
    };
}
