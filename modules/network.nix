{ lib, ... }:
let
  # avahi ships this service definition: _ssh._tcp on port 22, instance name
  # %h (the avahi host name, i.e. host.mdnsName). Both halves of this aspect
  # publish it, so the path lives once.
  sshServiceFile = pkgs: "${pkgs.avahi}/etc/avahi/services/ssh.service";

  yesNo = v: if lib.isBool v then lib.boolToYesNo v else toString v;

  sshdLogin = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
  sshdKeepalive = {
    ClientAliveInterval = 60;
    ClientAliveCountMax = 3;
  };

  avahiHostName = mdnsName: lib.optionalAttrs (mdnsName != null) { host-name = mdnsName; };
  avahiPublish = {
    publish-addresses = true;
    publish-hinfo = true;
    publish-workstation = true;
    publish-domain = true;
  };
in
{
  flake.modules.nixos.network =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
        # mkDefault so the live ISO can override to "prohibit-password" —
        # root login over SSH is the only way to remote-debug a stuck install.
        settings = lib.mapAttrs (_: lib.mkDefault) sshdLogin // sshdKeepalive;
      };

      # nssmdns4 is intentionally OFF: it hooks `mdns4_minimal
      # [NOTFOUND=return]` into nsswitch ahead of `resolve`, which hijacks every
      # `*.local` lookup to multicast mDNS and returns before systemd-resolved
      # is consulted. srv routes its local domains (including `*.local`) through
      # systemd-resolved.
      services.avahi = lib.mkIf config.stubbe.userFeatures.avahi {
        enable = true;
        nssmdns4 = false;
        openFirewall = true;
        # Advertise _ssh._tcp (port 22, instance name = the host name below).
        # It is how a machine that cannot run an mDNS resolver - the phone -
        # finds this one by name: resolving the service needs no NSS module.
        extraServiceFiles = lib.optionalAttrs config.services.openssh.enable {
          ssh = sshServiceFile pkgs;
        };
        # Real LAN NICs only. Without this, avahi advertises on docker0 / br-* /
        # veth* too, which collides the hostname with itself across bridges
        # (stubbe-nixos-2, -3, …) and leaks it into container networks.
        settings = {
          server = {
            allow-interfaces = [
              "enp4s0"
              "wlp3s0"
            ];
          }
          // avahiHostName config.host.mdnsName;
          publish = avahiPublish // {
            disable-publishing = false;
            disable-user-service-publishing = false;
          };
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
    let
      onAndroid = config.host.platform == "android";

      # `ssh laptop` and `ssh laptop.local` for every LAN host, from the one
      # catalogue. zsh needs no extra completion code: its _ssh_hosts reads
      # Host and HostName lines straight out of ~/.ssh/config.
      sshHosts = lib.concatMapAttrs (
        name: user:
        let
          # Android is the one target whose resolver cannot answer a .local
          # name (see mdnsSsh below), so only it routes through the helper.
          block = {
            inherit user;
          }
          // lib.optionalAttrs onAndroid {
            ProxyCommand = "${mdnsSsh}/bin/mdns-ssh %h %p";
          };
        in
        {
          # HostName on the short alias only: `Host laptop.local` would restate
          # the pattern it already matched.
          "${name}" = block // {
            HostName = "${name}.local";
          };
          "${name}.local" = block;
        }
      ) pkgs.stubbe.lanHosts;

      # ProxyCommand for the phone, which cannot resolve a .local name itself:
      # nix-on-droid ships glibc with no mDNS NSS module, no D-Bus for avahi,
      # and a hardcoded resolv.conf. It resolves the _ssh._tcp record every
      # other host publishes instead and relays stdio over that connection.
      mdnsSsh =
        pkgs.writers.writePython3Bin "mdns-ssh"
          {
            libraries = [ pkgs.python3Packages.zeroconf ];
          }
          ''
            import os
            import select
            import socket
            import sys

            from zeroconf import InterfaceChoice, IPVersion, Zeroconf

            SERVICE = "_ssh._tcp.local."
            SUFFIX = ".local"
            TIMEOUT_MS = 5000
            CHUNK = 65536


            def resolve(name: str) -> str:
                label = name[: -len(SUFFIX)] if name.endswith(SUFFIX) else name
                zc = Zeroconf(
                    interfaces=InterfaceChoice.Default,
                    ip_version=IPVersion.V4Only,
                    unicast=True,
                )
                try:
                    info = zc.get_service_info(
                        SERVICE, f"{label}.{SERVICE}", timeout=TIMEOUT_MS
                    )
                finally:
                    zc.close()
                if info is None:
                    sys.exit(f"mdns-ssh: {label} publishes no {SERVICE} record")
                addresses = info.parsed_scoped_addresses()
                if not addresses:
                    sys.exit(f"mdns-ssh: {label} publishes no address")
                return addresses[0]


            def relay(remote: socket.socket) -> None:
                stdin_fd = sys.stdin.fileno()
                stdout_fd = sys.stdout.fileno()
                watched = [stdin_fd, remote.fileno()]
                while watched:
                    readable, _, _ = select.select(watched, [], [])
                    if stdin_fd in readable:
                        data = os.read(stdin_fd, CHUNK)
                        if data:
                            remote.sendall(data)
                        else:
                            watched.remove(stdin_fd)
                            remote.shutdown(socket.SHUT_WR)
                    if remote.fileno() in readable:
                        data = remote.recv(CHUNK)
                        if not data:
                            return
                        os.write(stdout_fd, data)


            def main() -> None:
                if len(sys.argv) != 3:
                    sys.exit("usage: mdns-ssh <host> <port>")
                address = resolve(sys.argv[1])
                port = int(sys.argv[2])
                with socket.create_connection((address, port)) as remote:
                    relay(remote)


            main()
          '';

      avahiDaemonConf = pkgs.writeText "avahi-daemon.conf" (
        pkgs.stubbe.managedBy "avahi"
        +
          lib.generators.toINI
            {
              mkKeyValue = lib.generators.mkKeyValueDefault {
                mkValueString = yesNo;
              } "=";
            }
            {
              server = {
                allow-interfaces = "@ifaces@";
                use-ipv4 = true;
                use-ipv6 = true;
                ratelimit-interval-usec = 1000000;
                ratelimit-burst = 1000;
              }
              // avahiHostName config.host.mdnsName;
              publish = avahiPublish;
            }
      );
    in
    {
      # HM owns the file from here on: a hand-written ~/.ssh/config would
      # otherwise make activation refuse to clobber it.
      programs.ssh = {
        enable = true;
        # HM's legacy default block pins ControlMaster/ControlPath values that
        # nothing here uses; ssh's own defaults are what we run with.
        enableDefaultConfig = false;
        settings = sshHosts;
      };

      home = {
        file.".ssh/config".force = true;
        packages = lib.mkIf onAndroid [ pkgs.openssh ];
      };

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
            ${pkgs.stubbe.setup.hostPackage {
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

            # mDNS goes *after* dns, never ahead of it with [NOTFOUND=return]
            # (what libnss-mdns installs): that answers every `*.local` from
            # multicast alone, so srv's .local sites never reach resolved. Behind
            # dns, resolved answers srv's routed names and fails other .local
            # names at once (its own mDNS is off), and avahi takes over from there.
            if [ -f /etc/nsswitch.conf ]; then
              _stb_tmp=$(mktemp)
              awk '
                /^hosts:/ {
                  out = "hosts:"; n = 0; skip = 0; placed = 0; comment = ""
                  if (match($0, /#.*/)) comment = " " substr($0, RSTART)
                  for (i = 2; i <= NF; i++) {
                    if ($i ~ /^#/) break
                    if ($i ~ /^mdns/) { skip = 1; continue }
                    if (skip && $i ~ /^\[/) continue
                    skip = 0; tok[++n] = $i
                  }
                  for (i = 1; i <= n; i++) {
                    out = out " " tok[i]
                    if (tok[i] == "dns" && !placed) { out = out " mdns4_minimal"; placed = 1 }
                  }
                  if (!placed) out = out " mdns4_minimal"
                  print out comment; next
                }
                { print }
              ' /etc/nsswitch.conf > "$_stb_tmp"
              if ! cmp -s "$_stb_tmp" /etc/nsswitch.conf; then
                if [ ! -f /etc/nsswitch.conf.stubbedev-bak ]; then
                  sudo cp -a /etc/nsswitch.conf /etc/nsswitch.conf.stubbedev-bak
                fi
                sudo install -m 0644 -o root -g root "$_stb_tmp" /etc/nsswitch.conf
              fi
              rm -f "$_stb_tmp"
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
              sed "s/@ifaces@/$ifaces/" ${avahiDaemonConf} > "$_stb_tmp"
              sudo install -m 0644 -o root -g root "$_stb_tmp" /etc/avahi/avahi-daemon.conf
              rm -f "$_stb_tmp"
            fi

            ${lib.optionalString config.features.openssh ''
              sudo install -d -m 0755 /etc/avahi/services
              sudo install -m 0644 ${sshServiceFile pkgs} \
                /etc/avahi/services/ssh.service
            ''}

            sudo systemctl enable avahi-daemon.service
            sudo systemctl restart avahi-daemon.service
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
            ${pkgs.stubbe.setup.hostPackage {
              detect = "sshd";
              apt = [ "openssh-server" ];
              dnf = [ "openssh-server" ];
              pacman = [ "openssh" ];
            }}

            ${pkgs.stubbe.setup.text {
              name = "10-stubbedev.conf";
              target = "/etc/ssh/sshd_config.d/10-stubbedev.conf";
              text = lib.generators.toKeyValue {
                mkKeyValue = lib.generators.mkKeyValueDefault {
                  mkValueString = yesNo;
                } " ";
              } (sshdLogin // sshdKeepalive);
            }}

            if systemctl cat sshd.service >/dev/null 2>&1; then
              svc=sshd.service
            else
              svc=ssh.service
            fi
            sudo systemctl enable "$svc"
            sudo systemctl restart "$svc"

            if command -v ufw >/dev/null 2>&1; then
              sudo ufw allow ssh >/dev/null
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
