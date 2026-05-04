_: {
  linuxOnlyHomeModules.packagesFirefoxWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # Wrap firefox in nixGL, then strip MOZ_LEGACY_PROFILES so the binary
      # falls back to its built-in XDG-compliant default (Firefox 147+).
      # nixpkgs hardcodes MOZ_LEGACY_PROFILES=1 in its wrapper to keep the
      # historical ~/.mozilla/firefox path; we want ~/.config/mozilla/firefox
      # to match the previous programs.firefox setup.
      firefox-wrapped =
        let
          gfxFirefox = homeLib.gfx pkgs.firefox;
        in
        pkgs.runCommand "firefox-${pkgs.firefox.version}-xdg"
          { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            # libxul.so links against libpng-apng (animated PNG fork) which has
            # png_get_next_frame_delay_num. nixpkgs' firefox wrapper doesn't put
            # libpng-apng on LD_LIBRARY_PATH, and ld.so.cache happens to find
            # /usr/lib/libpng16.so.16 (stock libpng, no APNG symbols) before
            # libxul.so's RUNPATH is consulted. --prefix forces the right one.
            makeWrapper ${gfxFirefox}/bin/firefox $out/bin/firefox \
              --unset MOZ_LEGACY_PROFILES \
              --prefix LD_LIBRARY_PATH : "${pkgs.libpng.out}/lib"
          '';

      # Combine wrapper bin/firefox with upstream's share/ (icons, desktop
      # entry, MIME registrations). symlinkJoin links earlier paths first,
      # so the wrapper's bin/firefox shadows upstream's. Upstream's
      # firefox.desktop already uses `Exec=firefox` (PATH-resolved), which
      # picks up our wrapper from ~/.nix-profile/bin first.
      firefox-package = pkgs.symlinkJoin {
        name = "firefox-${pkgs.firefox.version}";
        paths = [
          firefox-wrapped
          pkgs.firefox
        ];
        meta = pkgs.firefox.meta // {
          mainProgram = "firefox";
        };
      };
    in
    lib.mkIf config.features.browsers {
      home.packages = [ firefox-package ];
    };
}
