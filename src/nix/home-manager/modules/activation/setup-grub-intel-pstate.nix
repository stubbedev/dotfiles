_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSudoSetupModule {
  moduleName = "activationSetupGrubIntelPstate";
  activationName = "setupGrubIntelPstate";
  scriptName = "setup-grub-intel-pstate";
  after = order.after.setupGrubIntelPstate;
  enableIf = { config, ... }: config.features.desktop;
  sudoArgs =
    { config, ... }:
    let
      grubConfigPath = "/etc/default/grub.d/intel-pstate-passive.cfg";
      stateDir = config.xdg.stateHome or "${config.home.homeDirectory}/.local/state";
      stampPath = "${stateDir}/grub-intel-pstate/installed";
      grubConfigContent = ''
        # managed-by: home-manager grub-intel-pstate v1
        # Force intel_pstate to use passive mode for software-controlled CPU frequency scaling
        # This allows using schedutil or other CPUFreq governors instead of HWP
        GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} intel_pstate=passive"
      '';
    in
    {
      preCheck = ''
                if [ -f "${stampPath}" ]; then
                  exit 0
                fi

                if [ -r "${grubConfigPath}" ] && grep -q "managed-by: home-manager grub-intel-pstate v1" "${grubConfigPath}"; then
                  mkdir -p "${stateDir}/grub-intel-pstate"
                  touch "${stampPath}"
                  exit 0
                fi

                if sudo -n test -f "${grubConfigPath}" 2>/dev/null; then
                  if sudo -n grep -q "managed-by: home-manager grub-intel-pstate v1" "${grubConfigPath}"; then
                    mkdir -p "${stateDir}/grub-intel-pstate"
                    touch "${stampPath}"
                    exit 0
                  fi
                fi

                if ! command -v update-grub >/dev/null 2>&1; then
                  if ! sudo -n sh -c 'command -v update-grub >/dev/null 2>&1'; then
                    echo "Skipping GRUB config: update-grub not found on this system."
                    exit 0
                  fi
                fi

                tmpfile=$(mktemp)
                cat > "$tmpfile" <<'EOF'
        ${grubConfigContent}
        EOF
      '';
      promptTitle = "Installing GRUB config for intel_pstate passive mode";
      promptBody = ''
        echo "This configures the kernel to use intel_pstate in passive mode,"
        echo "allowing software governors (schedutil, performance, etc.) to"
        echo "control CPU frequency scaling instead of hardware (HWP)."
        echo ""
        echo "After installation, you will need to:"
        echo "  1. Run: sudo update-grub"
        echo "  2. Reboot your system"
      '';
      promptQuestion = "Install GRUB config for intel_pstate passive mode?";
      actionScript = ''
        sudo install -d -m 0755 "/etc/default/grub.d"
        sudo install -m 0644 "$tmpfile" "${grubConfigPath}"
        sudo chown root:root "${grubConfigPath}"
        rm -f "$tmpfile"

        mkdir -p "${stateDir}/grub-intel-pstate"
        touch "${stampPath}"

        echo ""
        echo "GRUB config installed. Run the following commands:"
        echo "  sudo update-grub"
        echo "  sudo reboot"
      '';
      skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
    };
}
