_: {
  flake.modules.nixos.network =
    { lib, pkgs, ... }:
    {
      networking = {
        networkmanager = {
          enable = true;
          plugins = with pkgs; [ networkmanager-openconnect ];
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
            PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

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

            if [ -f /etc/nsswitch.conf ] && \
               ! grep -qE '^hosts:[^#]*\bmdns[46]?(_minimal)?\b' /etc/nsswitch.conf; then
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

            ${pkgs.stubbe.installText {
              name = "10-stubbedev.conf";
              target = "/etc/ssh/sshd_config.d/10-stubbedev.conf";
              text = ''
                PasswordAuthentication no
                KbdInteractiveAuthentication no
                PermitRootLogin no
              '';
            }}

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
