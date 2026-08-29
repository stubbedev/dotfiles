# Media: image, video and audio tooling, plus the office suite.
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
      # pavucontrol must run against SYSTEM GL, not nixGL: its GTK4 stack crashes
      # when GL init mixes nixGL and the system NVIDIA driver. So gfx = false (no
      # nixGL wrap) + unset the inherited nixGL env vars. mkWrappedPackage (not a
      # bare writeShellScriptBin) so pavucontrol.desktop + icons land on
      # XDG_DATA_DIRS — a bin-only script drops them and the app vanishes from rofi.
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

      # Bump ghostscript to 10.07.0 just for the user-facing `gs` CLI.
      # Done at the use site (not via overlay) so reverse deps like libreoffice
      # and imagemagick keep using cached pkgs.ghostscript.
      #
      # Source comes from the `ghostscript-src` flake input, so the tarball
      # hash lives in flake.lock rather than here. Bumping the version means
      # editing the URL in flake.nix and running `nix flake update`.
      ghostscript-latest = pkgs.ghostscript.overrideAttrs (_old: {
        version = "10.07.0";
        src = inputs.ghostscript-src;
      });

      # Pin ImageMagick to the exact release prod runs (remi `ImageMagick7` on
      # EL9, currently 7.1.2-25). Clip-path and alpha handling is version
      # sensitive, so matching the patch release is required to reproduce and
      # verify the KON-12723 download-template blanking locally.
      # Version is pinned to what production runs; the hash for it is in
      # flake.lock via the `imagemagick-src` input.
      imagemagick-prod = pkgs.imagemagick.overrideAttrs (_old: {
        version = "7.1.2-25";
        src = inputs.imagemagick-src;
      });

      # libembroidery ships the `sew` CLI for converting/inspecting machine
      # embroidery files. Not in nixpkgs; built from upstream main since
      # there are no tagged releases yet (v1.0 still pre-release).
      libembroidery = pkgs.stdenv.mkDerivation {
        pname = "libembroidery";
        # Revision tracked by the `libembroidery-src` flake input.
        version = "unstable";
        src = inputs.libembroidery-src;
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
        (gfx.wrap ffmpeg-full)
        (gfx.wrapExe "ffprobe" ffmpeg-full)
        (gfx.wrapExe "ffplay" ffmpeg-full)

        # Video player (GPU-accelerated output; default opener for video,
        # see mime maps in modules/desktop.nix).
        # gfx.bundle (not a bare wrap): bare gfx on non-NixOS emits only the
        # nixGL bin/mpv, dropping share/applications/mpv.desktop — so file
        # managers (pcmanfm/GIO) can't resolve the video/* default the mime maps
        # point at. gfx.bundle symlinkJoins the upstream pkg, putting the
        # .desktop + icons back on XDG_DATA_DIRS.
        (gfx.bundle { pkg = mpv; })

        # Image viewer (Wayland, GPU; default opener for still images,
        # mime maps live alongside the mpv ones in modules/desktop.nix).
        # gfx.bundle for the same reason as mpv: keep imv.desktop on
        # XDG_DATA_DIRS so the image/* defaults resolve in file managers.
        (gfx.bundle { pkg = imv; })

        # yazi's image-preview adapter on alacritty: the terminal has no
        # graphics protocol, so yazi falls back to ueberzugpp's overlay.
        (gfx.wrapExe "ueberzugpp" ueberzugpp)

        # Audio control (wrapped to avoid nixGL conflicts)
        # GTK4 apps try to initialize GL even if they don't render anything with it
        # This causes crashes when LD_LIBRARY_PATH contains nixGL NVIDIA drivers
        pavucontrol-wrapped

        # Ebook reader (Tauri/WebKitGTK GUI app).
        # gfx.bundle for the same reason as mpv/imv: keep readest.desktop
        # + icons on XDG_DATA_DIRS so it shows in rofi on non-NixOS.
        (gfx.bundle { pkg = readest; })

        # Office suite (GUI app)
        # gfx.bundle (not a bare wrap): keeps the writer/calc/impress/… .desktop
        # files + icons on XDG_DATA_DIRS so they show in rofi on non-NixOS.
        (gfx.bundle { pkg = libreoffice-stable; })
      ];
    };
}
