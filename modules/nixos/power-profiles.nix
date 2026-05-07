_: {
  flake.modules.nixos.powerProfiles =
    { ... }:
    {
      # Provides the system D-Bus service at /net/hadess/PowerProfiles.
      # Required by:
      #   - src/waybar/config.jsonc — power-profiles-daemon module
      #   - src/_shared/scripts/power.profile.fix.sh — `powerprofilesctl
      #     get` + dbus-monitor on the PropertiesChanged signal
      #   - modules/home/systemd.nix — waybar restart trigger
      # Without this enabled, waybar's PPD widget reads "unknown" and the
      # power-profile fix script's reactive loop never fires.
      #
      # The companion polkit rule for letting the primary user write CPU
      # governor / EPP / pstate values lives in modules/nixos/polkit.nix.
      services.power-profiles-daemon.enable = true;
    };
}
