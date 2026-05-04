_: {
  enableIf = { config, ... }: config.features.desktop;
  args = _: {
    preCheck = ''
      if ! command -v update-grub >/dev/null 2>&1; then
        if [ ! -x /usr/sbin/update-grub ] && [ ! -x /usr/bin/update-grub ]; then
          exit 0
        fi
      fi
    '';
    promptTitle = "Installing GRUB config for intel_pstate passive mode";
    promptBody = ''
      This configures the kernel to use intel_pstate in passive mode,
      allowing software governors (schedutil, performance, etc.) to
      control CPU frequency scaling instead of hardware (HWP).

      Will take effect after reboot.
    '';
    promptQuestion = "Install GRUB config for intel_pstate passive mode?";
    actionScript = ''
      tmpfile=$(mktemp)
      trap 'rm -f "$tmpfile"' EXIT
      cat > "$tmpfile" << 'EOF'
      # Force intel_pstate to use passive mode for software-controlled CPU frequency scaling
      GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} intel_pstate=passive"
      EOF
      sudo install -d -m 0755 /etc/default/grub.d
      sudo install -m 0644 "$tmpfile" /etc/default/grub.d/intel-pstate-passive.cfg
      sudo chown root:root /etc/default/grub.d/intel-pstate-passive.cfg
      sudo update-grub
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
