_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { homeLib, ... }:
    # Nix's appimageTools wrappers (currently `zennotes`, an Electron
    # AppImage) build their FHS sandbox with bubblewrap. On Ubuntu 24.04+
    # `kernel.apparmor_restrict_unprivileged_userns=1` only lets binaries
    # with a matching AppArmor profile create unprivileged user namespaces,
    # and Ubuntu's stock `bwrap` profile is keyed on /usr/bin/bwrap — the
    # Nix-store bwrap isn't covered, so the wrapper aborts on launch with
    #   bwrap: setting up uid map: Permission denied
    # Whitelist the Nix-store bwrap (any version) for userns. Children stay
    # unconfined, so the Electron chrome-sandbox nested inside also works.
    homeLib.mkAppArmorSetup {
      appName = "Nix bubblewrap (AppImage/FHS sandbox)";
      profileName = "nix-bubblewrap";
      programGlob = "/nix/store/*/bin/bwrap";
      managedBy = "home-manager bubblewrap-apparmor v1";
    };
}
