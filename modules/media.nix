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
      inherit (config.stubbe) gfx;
      # SYSTEM GL, not nixGL: the GTK4 stack crashes when GL init mixes nixGL
      # and the system NVIDIA driver.
      pavucontrol-wrapped = gfx.bundle {
        pkg = pkgs.pavucontrol;
        gfx = false;
        unset = [
          "LD_LIBRARY_PATH"
          "__GLX_VENDOR_LIBRARY_NAME"
          "__EGL_VENDOR_LIBRARY_FILENAMES"
          "LIBGL_DRIVERS_PATH"
        ];
      };

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

        (gfx.wrap ffmpeg-full)
        (gfx.wrapExe "ffprobe" ffmpeg-full)
        (gfx.wrapExe "ffplay" ffmpeg-full)

        # gfx.bundle, not a bare wrap: bare gfx emits only bin/, dropping the
        # .desktop entry that file managers resolve video/* through.
        (gfx.bundle { pkg = mpv; })

        (gfx.bundle { pkg = imv; })

        (gfx.wrapExe "ueberzugpp" ueberzugpp)

        pavucontrol-wrapped

        (gfx.bundle { pkg = readest; })
      ];
    };
}
