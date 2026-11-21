_: {
  flake.modules.homeManager.android-wake-lock =
    { config, lib, ... }:
    lib.mkIf (config.host.platform == "android") {
      # Android suspends the Termux app's processes once it is in the
      # background; the wake lock keeps phix's user services running.
      systemd.user.services.termux-wake-lock = {
        Unit.Description = "Keep Android from suspending the user services";
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "termux-wake-lock";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
