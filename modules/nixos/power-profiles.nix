_: {
  flake.modules.nixos.powerProfiles = _: {
    # Provides the system D-Bus service at /net/hadess/PowerProfiles.
    # Required by:
    #   - the wayle power-profile widgets (wayle-widget powerprofile-watch:
    #     `powerprofilesctl get` + dbus-monitor on the ActiveProfile signal)
    #   - src/_shared/scripts/power.profile.{cycle,fix}.sh
    # Without this enabled, the PPD widget reads "unknown" and the
    # power-profile fix script's reactive loop never fires.
    #
    # The companion polkit rule for letting the primary user write CPU
    # governor / EPP / pstate values lives in modules/nixos/polkit.nix.
    services.power-profiles-daemon.enable = true;
  };
}
