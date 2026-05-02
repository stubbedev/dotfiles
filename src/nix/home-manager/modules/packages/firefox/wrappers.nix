_: {
  flake.modules.homeManager.packagesFirefoxWrappers =
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
            makeWrapper ${gfxFirefox}/bin/firefox $out/bin/firefox \
              --unset MOZ_LEGACY_PROFILES
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
