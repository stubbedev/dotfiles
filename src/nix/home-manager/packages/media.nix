# Media processing and content creation tools
# Tools for image, video, and document processing
{ pkgs, ... }:
with pkgs; [
  # Image processing
  imagemagick # Image manipulation
  pngquant # PNG compression
  exiftool # Metadata tool
  dcraw # RAW image decoder
  libraw # RAW processing library
  librsvg # SVG rendering

  # Video processing
  ffmpeg-full # Video/audio processing

  # Image viewers and converters
  chafa # Terminal image viewer
  viu # Terminal image viewer
  ueberzugpp # Terminal image preview

  # Office and documents
  libreoffice # Office suite
  ghostscript # PostScript/PDF interpreter
]

