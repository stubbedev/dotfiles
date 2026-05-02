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
      firefox-wrapped = homeLib.gfx pkgs.firefox;

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
