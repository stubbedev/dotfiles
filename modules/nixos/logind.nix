_: {
  flake.modules.nixos.logind =
    { ... }:
    {
      # Keep the machine running with the lid closed so it stays
      # reachable over SSH on the local network. systemd-logind already
      # ignores the lid switch when an external display is connected
      # (HandleLidSwitchDocked defaults to "ignore"); this extends the
      # same behaviour to the no-monitor case.
      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
      };
    };
}
