{ inputs, ... }:
{
  flake.modules.homeManager.media =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      libembroidery = pkgs.stdenv.mkDerivation {
        pname = "libembroidery";
        version = "unstable";
        src = inputs.libembroidery-src;
        nativeBuildInputs = [ pkgs.cmake ];
        buildFlags = [ "sew" ];
        installPhase = ''
          runHook preInstall
          install -Dm755 sew -t $out/bin
          runHook postInstall
        '';
        meta = {
          description = "Library and `sew` CLI for reading/writing machine embroidery files";
          homepage = "https://www.libembroidery.org";
          license = lib.licenses.zlib;
          mainProgram = "sew";
          platforms = lib.platforms.unix;
        };
      };
    in
    lib.mkIf config.features.media {
      home.packages = with pkgs; [
        imagemagick
        libembroidery
        pngquant
        exiftool
        libraw
        librsvg
        ghostscript
        mupdf

        ffmpeg-full
        mpv
        imv
        ueberzugpp
        pavucontrol
        readest
      ];
    };
}
