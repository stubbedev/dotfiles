_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "GRUB config for intel_pstate passive mode";
      body = ''
        This configures the kernel to use intel_pstate in passive mode,
        allowing software governors (schedutil, performance, etc.) to
        control CPU frequency scaling instead of hardware (HWP).

        Will take effect after reboot.
      '';
      preCheck = ''
        if ! command -v update-grub >/dev/null 2>&1; then
          if [ ! -x /usr/sbin/update-grub ] && [ ! -x /usr/bin/update-grub ]; then
            exit 0
          fi
        fi
      '';
      actionScript = ''
        sudo install -d -m 0755 /etc/default/grub.d
        ${homeLib.installSystemFile {
          target = "/etc/default/grub.d/intel-pstate-passive.cfg";
          content = ''
            # Force intel_pstate to use passive mode for software-controlled CPU frequency scaling
            GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} intel_pstate=passive"
          '';
        }}
        sudo update-grub
      '';
    };
}
