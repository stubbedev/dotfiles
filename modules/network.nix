_: {
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
        settings =
          lib.mapAttrs (_: lib.mkDefault) {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          }
          // {
            ClientAliveInterval = 60;
            ClientAliveCountMax = 3;
          };
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
        # Advertise _ssh._tcp (port 22, instance name %h = the host name
        # below). It is how a machine that cannot run an mDNS resolver - the
        # phone - finds this one by name: resolving the service needs no NSS
        # module.
        extraServiceFiles = lib.optionalAttrs config.services.openssh.enable {
          ssh = "${pkgs.avahi}/etc/avahi/services/ssh.service";
        };
        settings = {
          server = {
            allow-interfaces = lib.optional (config.host.wifiInterface != null) config.host.wifiInterface;
          }
          // lib.optionalAttrs (config.host.mdnsName != null) { host-name = config.host.mdnsName; };
          publish = {
            publish-addresses = true;
            publish-hinfo = true;
            publish-workstation = true;
            publish-domain = true;
            publish-aaaa-on-ipv4 = false;
            disable-publishing = false;
            disable-user-service-publishing = false;
          };
        };
      };

      services.resolved.settings.Resolve.MulticastDNS =
        lib.mkIf config.stubbe.userFeatures.avahi "resolve";

      assertions = lib.optional config.stubbe.userFeatures.avahi {
        assertion = config.host.wifiInterface != null;
        message = "features.avahi announces the host on its wifi interface only; set host.wifiInterface.";
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
