_: {
  flake.modules.nixos.powerProfiles = _: {
    # Provides the system D-Bus service at /net/hadess/PowerProfiles.
    # Required by wayle's built-in power-profiles module (reads ActiveProfile
    # over this D-Bus interface; left-click ":cycle" sets the profile).
    # Without this enabled, the module reads "unknown".
    #
    # PPD alone handles CPU scaling (platform_profile + EPP) since the
    # Lunar Lake 400MHz firmware bug was fixed in BIOS 1.45 — the old
    # power.profile.fix.sh layer and intel_pstate=passive are gone.
    services.power-profiles-daemon.enable = true;
  };
}
