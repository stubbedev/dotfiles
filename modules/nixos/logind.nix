_: {
  flake.modules.nixos.logind = _: {
    # macOS-style lid behaviour, mirroring the non-NixOS drop-in installed
    # by modules/activation/_privileged/setup-logind-lid.nix: closing the
    # lid suspends on battery and AC, but the machine stays awake in
    # clamshell mode when an external display is connected ("docked"
    # counts connected non-eDP DRM connectors). Undocking with the lid
    # already closed is handled by src/hypr/scripts/monitor.toggle.sh —
    # logind only acts on the lid switch edge (systemd#7690).
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };
  };
}
