{ self, ... }:

{
  flake.modules.homeManager.setupBlueman =
    (import ../../../lib/activation-setups.nix).mkSudoSetupModule
      (
        {
          name = "setupBlueman";
        }
        // {
          # blueman comes from Nix (modules/packages/system.nix), but its privileged
          # half has to be reachable from the *system* bus, which never looks in
          # ~/.nix-profile. Without this, `org.blueman.Mechanism` resolves to whatever
          # distro blueman happens to be installed — a different build from the GUI on
          # PATH — or to nothing at all once that package is removed.
          #
          # The Nix package also ships no polkit files (upstream's org.blueman.policy
          # and Debian's grant rule are both absent), so those are vendored in
          # src/polkit/ and installed here. Without the .policy, polkitd rejects the
          # four actions as unregistered and the Bluetooth toggle fails.
          #
          # On NixOS, services.blueman.enable does all of this; gated off there.
          enableIf = { config, ... }: config.features.desktop;
          args =
            { pkgs, homeLib, ... }:
            let
              inherit (pkgs) blueman;
              links = [
                {
                  src = "${blueman}/lib/systemd/system/blueman-mechanism.service";
                  dst = "/etc/systemd/system/blueman-mechanism.service";
                }
                {
                  src = "${blueman}/share/dbus-1/system.d/org.blueman.Mechanism.conf";
                  dst = "/etc/dbus-1/system.d/org.blueman.Mechanism.conf";
                }
                {
                  src = "${blueman}/share/dbus-1/system-services/org.blueman.Mechanism.service";
                  dst = "/usr/share/dbus-1/system-services/org.blueman.Mechanism.service";
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
              subject = "blueman system integration";
              body = ''
                Symlinks blueman's D-Bus activation, bus policy and systemd unit from
                the Nix store into /etc and /usr/share, so the system bus starts the
                same build as the GUI on PATH, and installs the polkit action
                definitions the Nix package doesn't ship.

                The distro blueman package must stay uninstalled: it owns the same
                paths and would shadow these with a different version.
              '';
              actionScript = ''
                ${linkCmds}

                ${homeLib.installSystemFile {
                  target = "/usr/share/polkit-1/actions/org.blueman.policy";
                  content = builtins.readFile (self + "/src/polkit/org.blueman.policy");
                }}

                ${homeLib.installPolkitRule {
                  target = "/etc/polkit-1/rules.d/51-blueman.rules";
                  content = builtins.readFile (self + "/src/polkit/51-blueman.rules");
                }}

                sudo systemctl daemon-reload

                # dbus-daemon caches /etc/dbus-1/system.d at startup, so the bus policy
                # above is invisible — and activation of the mechanism fails with a
                # bare "Access denied" — until it is reloaded.
                sudo systemctl reload dbus >/dev/null 2>&1 || true

                # The mechanism is D-Bus activated on demand, so nothing to enable —
                # but an old instance from a previous build has to go, or the next
                # call keeps talking to it.
                sudo systemctl stop blueman-mechanism.service >/dev/null 2>&1 || true
              '';
            };
        }
      );
}
