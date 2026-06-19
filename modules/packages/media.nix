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
      # pavucontrol must run against SYSTEM GL, not nixGL: its GTK4 stack crashes
      # when GL init mixes nixGL and the system NVIDIA driver. So gfx = false (no
      # nixGL wrap) + unset the inherited nixGL env vars. mkWrappedPackage (not a
      # bare writeShellScriptBin) so pavucontrol.desktop + icons land on
      # XDG_DATA_DIRS — a bin-only script drops them and the app vanishes from rofi.
      pavucontrol-wrapped = homeLib.mkWrappedPackage {
        pkg = pkgs.pavucontrol;
        gfx = false;
        unset = [
          "LD_LIBRARY_PATH"
          "__GLX_VENDOR_LIBRARY_NAME"
          "__EGL_VENDOR_LIBRARY_FILENAMES"
          "LIBGL_DRIVERS_PATH"
        ];
      };

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
        # see mime maps in modules/home/xdg/base.nix + modules/nixos/mime-defaults.nix).
        # mkWrappedPackage (not bare gfx): bare gfx on non-NixOS emits only the
        # nixGL bin/mpv, dropping share/applications/mpv.desktop — so file
        # managers (pcmanfm/GIO) can't resolve the video/* default the mime maps
        # point at. mkWrappedPackage symlinkJoins the upstream pkg, putting the
        # .desktop + icons back on XDG_DATA_DIRS.
        (homeLib.mkWrappedPackage { pkg = mpv; })

        # Image viewer (Wayland, GPU; default opener for still images,
        # mime maps live alongside the mpv ones in the same two files).
        # mkWrappedPackage for the same reason as mpv: keep imv.desktop on
        # XDG_DATA_DIRS so the image/* defaults resolve in file managers.
        (homeLib.mkWrappedPackage { pkg = imv; })

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
        # mkWrappedPackage (not bare gfx): keeps the writer/calc/impress/… .desktop
        # files + icons on XDG_DATA_DIRS so they show in rofi on non-NixOS.
        (homeLib.mkWrappedPackage { pkg = libreoffice-fresh; })
      ];
    };
}
