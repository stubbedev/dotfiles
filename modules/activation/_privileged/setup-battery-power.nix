_: {
  # Host-package-level battery tuning, ported from omarchy's install/config
  # power scripts. The reactive half — power profile and charge threshold
  # following the charger — is setup-power-source.nix.
  #
  # Deliberately NOT ported from omarchy, because neither does anything here:
  #   - thermald: refuses to start on ThinkPads that expose
  #     thinkpad_acpi/dytc_lapmode ("Thermald can't run on this platform") —
  #     DYTC/platform_profile already owns the thermal policy.
  #   - wifi powersave toggling: NetworkManager ships wifi.powersave=3 (always
  #     on), which is the state omarchy's udev rule is trying to reach on
  #     battery. Its AC half turns powersave back off, which is a loss.
  #   - disabling USB autosuspend: costs battery. Already installed on purpose
  #     by setup-usb-autosuspend-disable.nix (audio pops on the dock).
  enableIf = { config, ... }: config.features.desktop;
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "battery power tuning";
      preCheck = homeLib.requirePath "/sys/class/power_supply/BAT0";
      body = ''
        Two unplugged-runtime fixes for this laptop:

        - intel-lpmd, Intel's low power mode daemon. On hybrid CPUs (Lunar
          Lake here) it parks the workload on the low-power E-core island
          while the machine is near-idle, which is where a laptop spends most
          of its day.
        - plocate's weekly reindex restricted to AC power, so it can't wake
          the disk and burn a chunk of the battery mid-flight.
      '';
      actionScript = ''
        # Activations run with a stripped PATH; restore it so command -v finds
        # apt-get / systemctl under /usr/sbin etc.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        # intel-lpmd only has a CPU topology to work with on Intel hybrid
        # parts. Model list from omarchy: Alder Lake (151/154), Raptor Lake
        # (183/186/191), Meteor Lake (170/172), Lunar Lake (189), Panther
        # Lake (204). Anything else, skip — the daemon would just exit.
        cpu_model=$(awk -F: '/^model[[:space:]]*:/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)
        case "$cpu_model" in
        151 | 154 | 170 | 172 | 183 | 186 | 189 | 191 | 204)
          ${homeLib.installHostPackage {
            detect = "intel_lpmd";
            apt = [ "intel-lpmd" ];
            dnf = [ "intel-lpmd" ];
            pacman = [ "intel-lpmd" ];
          }}
          sudo systemctl enable --now intel_lpmd.service >/dev/null 2>&1 || true
          ;;
        esac

        # plocate's reindex walks the whole filesystem; on battery that is
        # minutes of disk and CPU for a search index nobody is querying while
        # unplugged. systemd re-runs it once AC is back.
        if systemctl list-unit-files plocate-updatedb.service >/dev/null 2>&1; then
          sudo install -d -m 0755 /etc/systemd/system/plocate-updatedb.service.d

          ${homeLib.installSystemFile {
            target = "/etc/systemd/system/plocate-updatedb.service.d/ac-only.conf";
            content = ''
              # managed-by: home-manager battery-power
              [Unit]
              ConditionACPower=true
            '';
          }}

          sudo systemctl daemon-reload
        fi
      '';
    };
}
