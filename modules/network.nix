_: {
  flake.modules.nixos.network =
    { lib, pkgs, ... }:
    {
      networking = {
        networkmanager = {
          enable = true;
          plugins = with pkgs; [ networkmanager-openconnect ];
          # Let the Wi-Fi chip use its power-save mode. NM's own default is
          # "leave the driver alone"; Debian/Ubuntu ship a conf.d snippet
          # turning it on. Costs a little latency on the first packet after an
          # idle gap.
          wifi.powersave = true;
        };
        firewall = {
          enable = true;
          # Stealth: drop ICMP echo from non-LAN. Breaks ping diagnostics but
          # stops trivial host enumeration.
          allowPing = false;
        };
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
          # mkDefault so the live ISO can override to "prohibit-password" —
          # root login over SSH is the only way to remote-debug a stuck install.
          PermitRootLogin = lib.mkDefault "no";
        };
      };

      # nssmdns4 is intentionally OFF: it hooks `mdns4_minimal
      # [NOTFOUND=return]` into nsswitch ahead of `resolve`, which hijacks every
      # `*.local` lookup to multicast mDNS and returns before systemd-resolved
      # is consulted. srv routes its local domains (including `*.local`) through
      # dnsmasq via a systemd-resolved drop-in, so with nss-mdns in front
      # `grafana.local` never reaches dnsmasq. Turning it off lets `resolve`
      # answer `.local` from dnsmasq.
      # Trade-off: glibc no longer resolves OTHER hosts' `.local` names via mDNS
      # (`ssh printer.local`); the daemon still advertises this host and powers
      # DNS-SD service discovery.
      services.avahi = {
        enable = true;
        nssmdns4 = false;
        openFirewall = true;
        # Real LAN NICs only. Without this, avahi advertises on docker0 / br-* /
        # veth* too, which collides the hostname with itself across bridges
        # (stubbe-nixos-2, -3, …) and leaks it into container networks.
        allowInterfaces = [
          "enp4s0"
          "wlp3s0"
        ];
        publish = {
          enable = true;
          addresses = true;
          domain = true;
          hinfo = true;
          userServices = true;
          workstation = true;
        };
      };

      # NM-wait-online blocks boot until any connection is up; on a desktop with
      # offline-friendly services that just adds 20s to every boot. Services
      # that genuinely need network use NetworkManager-online.target instead.
      systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
    };

  flake.modules.homeManager.network =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stubbe.setup = {
        avahi = lib.mkIf config.features.avahi {
          privileged = true;
          title = "Installing Avahi (mDNS)";
          body = ''
            Install avahi-daemon + libnss-mdns via the host's package manager,
            write a managed /etc/avahi/avahi-daemon.conf that whitelists real
            LAN interfaces (excluding docker/veth/bridge), and enable the
            service so this host can resolve and be resolved as
            <hostname>.local on the LAN.
          '';
          script = ''
            # Activations run with a stripped PATH; restore it so `command -v`
            # finds apt-get / dnf / pacman / ip under /usr/sbin etc.
            PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

            # On Debian/Ubuntu, libnss-mdns's postinst edits /etc/nsswitch.conf
            # for us; the nsswitch step below is a safety net for when it did
            # not, and the canonical path for Fedora/Arch.
            ${pkgs.stubbe.installHostPackage {
              detect = "avahi-daemon";
              apt = [
                "avahi-daemon"
                "libnss-mdns"
              ];
              dnf = [
                "avahi"
                "nss-mdns"
              ];
              pacman = [
                "avahi"
                "nss-mdns"
              ];
            }}

            # Ensure /etc/nsswitch.conf carries an mdns entry so `ssh foo.local`
            # resolves. Fedora's and Arch's nss-mdns ship the NSS plugin but do
            # not auto-edit nsswitch.conf — only Debian's libnss-mdns does.
            # Idempotent: skips when any mdns variant is already in the hosts:
            # line, including Debian's prior edit.
            #
            # Placement matters: it must come BEFORE any `resolve` entry,
            # because Arch's default uses `resolve [!UNAVAIL=return]`, which
            # swallows NOTFOUND for .local before mdns_minimal can run. Insert
            # right before `resolve` if present, else before `dns`, else at the
            # start of the entry list.
            if [ -f /etc/nsswitch.conf ] && \
               ! grep -qE '^hosts:[^#]*\bmdns[46]?(_minimal)?\b' /etc/nsswitch.conf; then
              # Only back up the first time; otherwise a partial-failure retry
              # would clobber the pristine backup with half-edited state.
              if [ ! -f /etc/nsswitch.conf.stubbedev-bak ]; then
                sudo cp -a /etc/nsswitch.conf /etc/nsswitch.conf.stubbedev-bak
              fi
              if grep -qE '^hosts:[^#]*\bresolve\b' /etc/nsswitch.conf; then
                sudo sed -i -E \
                  's/^(hosts:[^#]*)\bresolve\b/\1mdns4_minimal [NOTFOUND=return] resolve/' \
                  /etc/nsswitch.conf
              elif grep -qE '^hosts:[^#]*\bdns\b' /etc/nsswitch.conf; then
                sudo sed -i -E \
                  's/^(hosts:[^#]*)\bdns\b/\1mdns4_minimal [NOTFOUND=return] dns/' \
                  /etc/nsswitch.conf
              else
                sudo sed -i -E \
                  's/^(hosts:[[:space:]]+)/\1mdns4_minimal [NOTFOUND=return] /' \
                  /etc/nsswitch.conf
              fi
            fi

            # Whitelist real LAN NICs only — same reasoning as allowInterfaces
            # in the NixOS half, but detected at activation time here because a
            # non-NixOS host's NIC names are not known at eval time.
            # `ip -br link` prints names like `vethXYZ@if3`, so split on @.
            #
            # The lock hashes this script's text, not its output, so new NICs
            # are not re-detected on their own. To refresh, delete
            # ~/.local/state/nix/home-manager/avahi.lock.sum and switch again.
            ifaces=$(ip -br link show 2>/dev/null \
              | awk '{
                  split($1, parts, "@");
                  n = parts[1];
                  if (n != "lo" && n !~ /^(docker|veth|br-|virbr|vmnet|tap|wg|vxlan|kube-|cni-|flannel|cilium|ip6tnl|tunl|sit|gre)/) print n;
                }' \
              | paste -sd, -)

            if [ -z "$ifaces" ]; then
              echo "No real LAN interfaces detected; skipping avahi-daemon.conf write." >&2
            else
              # printf, not a heredoc: a heredoc delimiter has to sit at column
              # zero, which is fragile inside an indented Nix string.
              _stb_tmp=$(mktemp)
              printf '%s\n' \
                '# Managed by stubbe — modules/network.nix' \
                '[server]' \
                "allow-interfaces=$ifaces" \
                'use-ipv4=yes' \
                'use-ipv6=yes' \
                'ratelimit-interval-usec=1000000' \
                'ratelimit-burst=1000' \
                "" \
                '[publish]' \
                'publish-addresses=yes' \
                'publish-hinfo=yes' \
                'publish-workstation=yes' \
                'publish-domain=yes' \
                "" \
                '[reflector]' \
                "" \
                '[rlimits]' > "$_stb_tmp"
              sudo install -m 0644 -o root -g root "$_stb_tmp" /etc/avahi/avahi-daemon.conf
              rm -f "$_stb_tmp"
            fi

            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable avahi-daemon.service >/dev/null 2>&1 || true
              sudo systemctl restart avahi-daemon.service >/dev/null 2>&1 || true
            fi
          '';
        };

        openssh = lib.mkIf config.features.openssh {
          privileged = true;
          title = "Installing OpenSSH server";
          body = ''
            Install openssh-server via the host's package manager, drop a managed
            /etc/ssh/sshd_config.d/10-stubbedev.conf that disables password and
            root logins (matching the NixOS host), open the host firewall for ssh
            (ufw/firewalld if present), and enable the sshd unit.
          '';
          script = ''
            PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

            ${pkgs.stubbe.installHostPackage {
              detect = "sshd";
              apt = [ "openssh-server" ];
              dnf = [ "openssh-server" ];
              pacman = [ "openssh" ];
            }}

            # Modern openssh on Debian/Ubuntu/Fedora/Arch all ship a main
            # sshd_config beginning with `Include /etc/ssh/sshd_config.d/*.conf`,
            # and the FIRST occurrence of a directive wins — so a snippet there
            # overrides distro defaults further down.
            ${pkgs.stubbe.installText {
              name = "10-stubbedev.conf";
              target = "/etc/ssh/sshd_config.d/10-stubbedev.conf";
              text = ''
                # Managed by stubbe — modules/network.nix
                PasswordAuthentication no
                KbdInteractiveAuthentication no
                PermitRootLogin no
              '';
            }}

            # Unit name differs across distros: Debian/Ubuntu ship ssh.service,
            # Fedora/Arch sshd.service. Pick whichever exists, then restart so
            # the new snippet takes effect (a fresh apt-get install auto-starts
            # pre-snippet).
            if command -v systemctl >/dev/null 2>&1; then
              if systemctl cat sshd.service >/dev/null 2>&1; then
                svc=sshd.service
              elif systemctl cat ssh.service >/dev/null 2>&1; then
                svc=ssh.service
              else
                svc=""
              fi
              if [ -n "$svc" ]; then
                sudo systemctl enable "$svc" >/dev/null 2>&1 || true
                sudo systemctl restart "$svc" >/dev/null 2>&1 || true
              fi
            fi

            # Open the host firewall for ssh. Idempotent on both tools, and
            # skipped when no recognised firewall daemon is installed (Arch's
            # default state, and Ubuntu without ufw).
            if command -v ufw >/dev/null 2>&1; then
              sudo ufw allow ssh >/dev/null 2>&1 || true
            fi
            if command -v firewall-cmd >/dev/null 2>&1 \
               && sudo firewall-cmd --state >/dev/null 2>&1; then
              sudo firewall-cmd --permanent --add-service=ssh >/dev/null
              sudo firewall-cmd --reload >/dev/null
            fi
          '';
        };

        # Let this machine ssh to itself, and let a peer sharing the same key
        # pair in. Idempotent: grep skips when the line is already present.
        sshSelfAuth = lib.mkIf config.features.openssh {
          script = ''
            pub="$HOME/.ssh/id_ed25519.pub"
            auth="$HOME/.ssh/authorized_keys"
            if [ -f "$pub" ]; then
              install -d -m 0700 "$HOME/.ssh"
              touch "$auth"
              chmod 600 "$auth"
              if ! grep -qxF "$(cat "$pub")" "$auth"; then
                cat "$pub" >> "$auth"
              fi
            fi
          '';
        };
      };
    };
}
