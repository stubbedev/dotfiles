# Bluetooth. On NixOS the system module owns the daemon and the GUI manager's
# privileged half; on a non-NixOS host blueman comes from Nix but its mechanism
# must be reachable from the SYSTEM bus, which never looks in ~/.nix-profile —
# hence the activation that links the store files into /etc.
_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      # Battery reporting on BLE peripherals (mice, headphones, controllers)
      # via the standard BAS GATT characteristic.
      settings.General.Experimental = true;
    };

    # The system service, so the tray applet finds an autostart-ready daemon.
    services.blueman.enable = true;
  };

  flake.modules.homeManager.bluetooth =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stubbe.setup.blueman = lib.mkIf config.features.desktop {
        privileged = true;
        title = "Installing blueman system integration";
        body = ''
          Symlinks blueman's D-Bus activation, bus policy and systemd unit from
          the Nix store into /etc and /usr/share, so the system bus starts the
          same build as the GUI on PATH, and installs the polkit action
          definitions the Nix package doesn't ship.

          The distro blueman package must stay uninstalled: it owns the same
          paths and would shadow these with a different version.
        '';
        # Without the .policy file, polkitd rejects blueman's four actions as
        # unregistered and the Bluetooth toggle fails — the Nix package ships
        # neither upstream's org.blueman.policy nor Debian's grant rule, so both
        # are vendored under src/bluetooth/.
        script =
          let
            links = [
              {
                src = "${pkgs.blueman}/lib/systemd/system/blueman-mechanism.service";
                dst = "/etc/systemd/system/blueman-mechanism.service";
              }
              {
                src = "${pkgs.blueman}/share/dbus-1/system.d/org.blueman.Mechanism.conf";
                dst = "/etc/dbus-1/system.d/org.blueman.Mechanism.conf";
              }
              {
                src = "${pkgs.blueman}/share/dbus-1/system-services/org.blueman.Mechanism.service";
                dst = "/usr/share/dbus-1/system-services/org.blueman.Mechanism.service";
              }
            ];
          in
          ''
            ${lib.concatMapStrings (l: ''
              sudo install -d -m 0755 "$(dirname "${l.dst}")"
              sudo ln -sfT "${l.src}" "${l.dst}"
            '') links}

            ${pkgs.stubbe.installFile {
              source = pkgs.stubbe.file "src/bluetooth/org.blueman.policy";
              target = "/usr/share/polkit-1/actions/org.blueman.policy";
            }}

            ${pkgs.stubbe.installPolkitRule {
              source = pkgs.stubbe.file "src/bluetooth/51-blueman.rules";
              target = "/etc/polkit-1/rules.d/51-blueman.rules";
            }}

            sudo systemctl daemon-reload

            # dbus-daemon caches /etc/dbus-1/system.d at startup, so the bus
            # policy above is invisible — and mechanism activation fails with a
            # bare "Access denied" — until it is reloaded.
            sudo systemctl reload dbus >/dev/null 2>&1 || true

            # The mechanism is D-Bus activated on demand, so there is nothing to
            # enable — but an old instance from a previous build has to go, or
            # the next call keeps talking to it.
            sudo systemctl stop blueman-mechanism.service >/dev/null 2>&1 || true
          '';
      };
    };
}
