{ pkgs, config, ... }:
let
  wrap = config.lib.nixGL.wrap;
in
with pkgs; [
  # Image processing (CLI tools, no wrapping needed)
  imagemagick
  pngquant
  exiftool
  dcraw
  libraw
  librsvg
  ghostscript

  # Video/media (ffmpeg uses GPU acceleration)
  (wrap ffmpeg-full)

  # Terminal image viewers (some use GPU)
  chafa
  (wrap viu)
  (wrap ueberzugpp)

  # Office suite (GUI app)
  (wrap libreoffice-fresh)
]

