_:
let
  helpers = import ./_helpers.nix;
  order = import ./_order.nix;
in
helpers.mkSetupModule {
  moduleName = "activationSetupGnomeKeyring";
  activationName = "setupGnomeKeyring";
  after = order.after.setupGnomeKeyring;
  enableIf = { config, ... }: config.features.desktop;
  script =
    { pkgs, ... }:
    let
      servicePath = "$HOME/.config/systemd/user/gnome-keyring-daemon.service";
      daemonBin = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon";
    in
    ''
      set -e

      if systemctl --user is-enabled gnome-keyring-daemon.service >/dev/null 2>&1; then
        exit 0
      fi

      mkdir -p "$HOME/.config/systemd/user"
      cat > "${servicePath}" <<EOF
      [Unit]
      Description=GNOME Keyring daemon (secrets component)
      PartOf=graphical-session.target

      [Service]
      Type=simple
      ExecStart=${daemonBin} --start --foreground --components=secrets
      Restart=on-failure
      RestartSec=2s

      [Install]
      WantedBy=default.target
      EOF

      systemctl --user daemon-reload
      systemctl --user enable --now gnome-keyring-daemon.service
      echo ""
      echo "GNOME Keyring daemon installed and started."
    '';
}
