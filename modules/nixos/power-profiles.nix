_: {
  flake.modules.nixos.powerProfiles = _: {
    # Provides the system D-Bus service at /net/hadess/PowerProfiles.
    # Required by:
    #   - wayle's built-in power-profiles module (reads ActiveProfile over this
    #     D-Bus interface; left-click ":cycle" sets the profile)
    #   - src/_shared/scripts/power.profile.fix.sh
    # Without this enabled, the module reads "unknown" and the
    # power-profile fix script's reactive loop never fires.
    #
    # The companion polkit rule for letting the primary user write CPU
    # governor / EPP / pstate values lives in modules/nixos/polkit.nix.
    services.power-profiles-daemon.enable = true;
  };
}
