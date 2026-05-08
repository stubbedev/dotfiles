_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { pkgs, homeLib, ... }:
    let
      udisks = pkgs.udisks2;
      links = [
        {
          src = "${udisks}/etc/systemd/system/udisks2.service";
          dst = "/etc/systemd/system/udisks2.service";
        }
        {
          src = "${udisks}/share/dbus-1/system.d/org.freedesktop.UDisks2.conf";
          dst = "/etc/dbus-1/system.d/org.freedesktop.UDisks2.conf";
        }
        {
          src = "${udisks}/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
          dst = "/usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service";
        }
        {
          src = "${udisks}/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
          dst = "/usr/share/polkit-1/actions/org.freedesktop.UDisks2.policy";
        }
        {
          src = "${udisks}/lib/udev/rules.d/80-udisks2.rules";
          dst = "/etc/udev/rules.d/80-udisks2.rules";
        }
        {
          src = "${udisks}/etc/udisks2/udisks2.conf";
          dst = "/etc/udisks2/udisks2.conf";
        }
      ];
      linkCmds = builtins.concatStringsSep "\n" (
        map (l: ''
          sudo install -d -m 0755 "$(dirname "${l.dst}")"
          sudo ln -sfT "${l.src}" "${l.dst}"
        '') links
      );
    in
    homeLib.mkInstallPrompt {
      subject = "udisks2 system integration (pcmanfm removable media)";
      body = ''
        Symlinks udisks2's systemd unit, dbus policy + activation, polkit
        policy, udev rules, and default config from the Nix store into
        /etc and /usr/share so the home-manager-installed udisks2 daemon
        can run as a system service. Then reloads systemd/udev and starts
        udisks2.service. gvfs is user-bus and needs nothing privileged.

        On NixOS, services.udisks2.enable + services.gvfs.enable handle
        this natively; this activation is gated off there.
      '';
      actionScript = ''
        ${linkCmds}

        sudo install -d -m 0755 /var/lib/udisks2

        sudo systemctl daemon-reload
        if command -v udevadm >/dev/null 2>&1; then
          sudo udevadm control --reload-rules
        fi
        sudo systemctl enable --now udisks2.service
      '';
    };
}
