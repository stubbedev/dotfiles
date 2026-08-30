_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };

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
        # are vendored inline below.
        script =
          let
            links = [
              {
                source = "${pkgs.blueman}/lib/systemd/system/blueman-mechanism.service";
                target = "/etc/systemd/system/blueman-mechanism.service";
              }
              {
                source = "${pkgs.blueman}/share/dbus-1/system.d/org.blueman.Mechanism.conf";
                target = "/etc/dbus-1/system.d/org.blueman.Mechanism.conf";
              }
              {
                source = "${pkgs.blueman}/share/dbus-1/system-services/org.blueman.Mechanism.service";
                target = "/usr/share/dbus-1/system-services/org.blueman.Mechanism.service";
              }
            ];
          in
          ''
            ${lib.concatMapStrings pkgs.stubbe.installLink links}

            ${pkgs.stubbe.installText {
              name = "org.blueman.policy";
              target = "/usr/share/polkit-1/actions/org.blueman.policy";
              text = ''
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">
                <policyconfig>
                  <vendor>The Blueman Project</vendor>
                  <vendor_url>https://github.com/blueman-project/blueman</vendor_url>
                  <icon_name>blueman</icon_name>
                  <action id="org.blueman.network.setup">
                    <description>Configure Bluetooth Network</description>
                    <message>Configuring networking requires privileges</message>
                    <defaults>
                      <allow_inactive>no</allow_inactive>
                      <allow_active>auth_admin_keep</allow_active>
                    </defaults>
                  </action>
                  <action id="org.blueman.dhcp.client">
                    <description>Launch DHCP client</description>
                    <message>Launching DHCP client requires privileges</message>
                    <defaults>
                      <allow_inactive>no</allow_inactive>
                      <allow_active>auth_admin_keep</allow_active>
                    </defaults>
                  </action>
                  <action id="org.blueman.pppd.pppconnect">
                    <description>Launch PPP daemon</description>
                    <message>Launching PPP daemon requires privileges</message>
                    <defaults>
                      <allow_inactive>no</allow_inactive>
                      <allow_active>auth_admin_keep</allow_active>
                    </defaults>
                  </action>
                  <action id="org.blueman.rfkill.setstate">
                    <description>Set RfKill State</description>
                    <message>Setting RfKill State requires privileges</message>
                    <defaults>
                      <allow_inactive>no</allow_inactive>
                      <allow_active>auth_admin_keep</allow_active>
                    </defaults>
                  </action>
                </policyconfig>
              '';
            }}

            ${pkgs.stubbe.installPolkitRule {
              source = pkgs.writeText "51-blueman.rules" ''
                // blueman's privileged half (blueman-mechanism) guards rfkill, PAN setup,
                // the DHCP client and pppd behind polkit. Upstream defaults all four to
                // auth_admin_keep, which means a password prompt every time the Bluetooth
                // toggle is flipped. Debian ships a rule granting them to sudo/netdev; the
                // Nix package ships no polkit files at all, so this is the replacement for
                // both.
                //
                // Same trust boundary Debian used: a local, active session belonging to
                // someone who is already in sudo. Nothing here grants anything to a remote
                // or inactive session.
                polkit.addRule(function (action, subject) {
                  var allowed = ${
                    builtins.toJSON (
                      lib.genAttrs [
                        "org.blueman.network.setup"
                        "org.blueman.dhcp.client"
                        "org.blueman.rfkill.setstate"
                        "org.blueman.pppd.pppconnect"
                      ] (_: true)
                    )
                  };

                  if (allowed[action.id] && subject.local && subject.active && subject.isInGroup("sudo")) {
                    return polkit.Result.YES;
                  }
                });
              '';
              target = "/etc/polkit-1/rules.d/51-blueman.rules";
            }}

            sudo systemctl daemon-reload

            sudo systemctl reload dbus >/dev/null 2>&1 || true

            sudo systemctl stop blueman-mechanism.service >/dev/null 2>&1 || true
          '';
      };
    };
}
