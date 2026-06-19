_: {
  linuxOnlyHomeModules.packagesMedia =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # Wrapper for pavucontrol that avoids nixGL NVIDIA driver conflicts
      # GTK4 tries to initialize GL which causes crashes when mixing nixGL and system NVIDIA drivers
      pavucontrol-wrapped = pkgs.writeShellScriptBin "pavucontrol" ''
        # Unset nixGL environment variables to prevent driver conflicts
        unset LD_LIBRARY_PATH
        unset __GLX_VENDOR_LIBRARY_NAME
        unset __EGL_VENDOR_LIBRARY_FILENAMES
        unset LIBGL_DRIVERS_PATH

        exec ${pkgs.pavucontrol}/bin/pavucontrol "$@"
      '';

      # Bump ghostscript to 10.07.0 just for the user-facing `gs` CLI.
      # Done at the use site (not via overlay) so reverse deps like libreoffice
      # and imagemagick keep using cached pkgs.ghostscript.
      ghostscript-latest = pkgs.ghostscript.overrideAttrs (_old: rec {
        version = "10.07.0";
        src = pkgs.fetchurl {
          url = "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${
            lib.replaceStrings [ "." ] [ "" ] version
          }/ghostscript-${version}.tar.xz";
          hash = "sha256-3azk4XIflnpVA5uv9WSEAiXguqHU9UMiR8oczRRzt8E=";
        };
      });

      # Pin ImageMagick to the exact release prod runs (remi `ImageMagick7` on
      # EL9, currently 7.1.2-25). Clip-path and alpha handling is version
      # sensitive, so matching the patch release is required to reproduce and
      # verify the KON-12723 download-template blanking locally.
      imagemagick-prod = pkgs.imagemagick.overrideAttrs (_old: rec {
        version = "7.1.2-25";
        src = pkgs.fetchFromGitHub {
          owner = "ImageMagick";
          repo = "ImageMagick";
          rev = version;
          hash = "sha256-7z1oIKXZcumsESLrFRvU6z0M8JVsogG7yDWwF62jPwo=";
        };
      });

      # libembroidery ships the `sew` CLI for converting/inspecting machine
      # embroidery files. Not in nixpkgs; built from upstream main since
      # there are no tagged releases yet (v1.0 still pre-release).
      libembroidery = pkgs.stdenv.mkDerivation {
        pname = "libembroidery";
        version = "unstable-2026-04-21";
        src = pkgs.fetchFromGitHub {
          owner = "Embroidermodder";
          repo = "libembroidery";
          rev = "58d1d71ac100a1b83024023548289799a52f9f73";
          hash = "sha256-ha8xxmUxbz6BcnHNq1mGp+yT7mnSFNcIafEluQ6EgHU=";
        };
        nativeBuildInputs = [ pkgs.cmake ];
        # Upstream tests have a -Wformat-security issue and arc_test fails on
        # pre-1.0 main; the `sew` CLI itself builds and runs fine.
        hardeningDisable = [ "format" ];
        doCheck = false;
        # CMakeLists installs `embroidery.h` from source root, but the header
        # actually lives in `include/`. Patch the install path.
        postPatch = ''
          substituteInPlace CMakeLists.txt \
            --replace-fail "FILES embroidery.h" "FILES include/embroidery.h"
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
        # Image processing (CLI tools, no wrapping needed)
        imagemagick-prod
        libembroidery
        pngquant
        exiftool
        c2patool
        dcraw
        libraw
        librsvg
        ghostscript-latest
        mupdf

        # Video/media (ffmpeg uses GPU acceleration)
        (homeLib.gfx ffmpeg-full)
        (homeLib.gfxExe "ffprobe" ffmpeg-full)
        (homeLib.gfxExe "ffplay" ffmpeg-full)

        # Video player (GPU-accelerated output; default opener for video,
        # see mime maps in modules/home/xdg/base.nix + modules/nixos/mime-defaults.nix)
        (homeLib.gfx mpv)

        # Image viewer (Wayland, GPU; default opener for still images,
        # mime maps live alongside the mpv ones in the same two files)
        (homeLib.gfx imv)

        # Terminal image viewers (some use GPU)
        chafa
        imgcat
        (homeLib.gfx viu)
        (homeLib.gfxExe "ueberzugpp" ueberzugpp)

        # Audio control (wrapped to avoid nixGL conflicts)
        # GTK4 apps try to initialize GL even if they don't render anything with it
        # This causes crashes when LD_LIBRARY_PATH contains nixGL NVIDIA drivers
        pavucontrol-wrapped

        # Office suite (GUI app)
        (homeLib.gfx libreoffice-fresh)
      ];
    };
}
