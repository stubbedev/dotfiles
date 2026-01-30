{ ... }:
{
  flake.modules.homeManager.packagesMedia = { pkgs, homeLib, ... }:
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
    in
    {
      home.packages = with pkgs; [
        # Image processing (CLI tools, no wrapping needed)
        imagemagick
        pngquant
        exiftool
        dcraw
        libraw
        librsvg
        ghostscript

        # Video/media (ffmpeg uses GPU acceleration)
        (homeLib.gfx ffmpeg-full)

        # Terminal image viewers (some use GPU)
        chafa
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
