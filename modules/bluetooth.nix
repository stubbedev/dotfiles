_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };
  };

  flake.modules.homeManager.bluetooth =
    { config, lib, ... }:
    {
      stubbe.setup.bluemanRemoved = lib.mkIf config.features.desktop {
        privileged = true;
        title = "Removing blueman's system integration";
        body = ''
          The bar's bluetooth dropdown pairs and manages devices now, so this
          removes the system files that pointed at the blueman package.
        '';
        script = ''
          sudo systemctl stop blueman-mechanism.service 2>/dev/null || :
          sudo rm -f \
            /etc/systemd/system/blueman-mechanism.service \
            /etc/dbus-1/system.d/org.blueman.Mechanism.conf \
            /usr/share/dbus-1/system-services/org.blueman.Mechanism.service \
            /usr/share/polkit-1/actions/org.blueman.policy \
            /etc/polkit-1/rules.d/51-blueman.rules
          sudo systemctl daemon-reload
        '';
      };
    };
}
