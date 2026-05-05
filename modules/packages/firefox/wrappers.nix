_: {
  linuxOnlyHomeModules.packagesFirefoxWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.browsers {
      # Wrap firefox in nixGL, then strip MOZ_LEGACY_PROFILES so the binary
      # falls back to its built-in XDG-compliant default (Firefox 147+).
      # nixpkgs hardcodes MOZ_LEGACY_PROFILES=1 in its wrapper to keep the
      # historical ~/.mozilla/firefox path; we want ~/.config/mozilla/firefox
      # to match the previous programs.firefox setup.
      #
      # libxul.so links against libpng-apng (animated PNG fork) which has
      # png_get_next_frame_delay_num. nixpkgs' firefox wrapper doesn't put
      # libpng-apng on LD_LIBRARY_PATH, and ld.so.cache happens to find
      # /usr/lib/libpng16.so.16 (stock libpng, no APNG symbols) before
      # libxul.so's RUNPATH is consulted. --prefix forces the right one.
      #
      # Upstream's firefox.desktop uses Exec=firefox (PATH-resolved), so
      # bundling upstream alongside the wrapper picks up icons and the
      # desktop entry while still routing the binary through our wrapper.
      home.packages = [
        (homeLib.mkWrappedPackage {
          pkg = pkgs.firefox;
          unset = [ "MOZ_LEGACY_PROFILES" ];
          prefix.LD_LIBRARY_PATH = "${pkgs.libpng.out}/lib";
        })
      ];
    };
}
