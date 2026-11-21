_: {
  flake.modules.nixos.network =
    {
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
        settings = lib.mapAttrs (_: lib.mkDefault) pkgs.stubbe.sshdSettings;
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

      sshHosts = lib.mapAttrs (
        name: host:
        {
          inherit (host) user;
          HostName = "${name}.${pkgs.stubbe.peerZone}";
          Port = host.port;
        }
        // lib.optionalAttrs onAndroid {
          ProxyCommand = "${lib.getExe' pkgs.srv "srv"} peer dial %h %p";
        }
      ) pkgs.stubbe.lanHosts;

      sshdDir = "${config.xdg.stateHome}/sshd";
      sshdHostKey = "${sshdDir}/ssh_host_ed25519_key";
      sshdConfig = pkgs.writeText "sshd_config" (
        lib.generators.toKeyValue
          {
            mkKeyValue =
              key: value: "${key} ${if lib.isBool value then lib.boolToYesNo value else toString value}";
          }
          (
            pkgs.stubbe.sshdSettings
            // {
              Port = pkgs.stubbe.lanHosts.${config.host.flakeAttr}.port;
              HostKey = sshdHostKey;
              PidFile = "none";
            }
          )
      );
      phoneSshd = onAndroid && config.features.openssh;
    in
    {
      # HM owns the file from here on: a hand-written ~/.ssh/config would
      # otherwise make activation refuse to clobber it.
      programs.ssh = {
        enable = true;
        # HM's legacy default block pins ControlMaster/ControlPath values that
        # nothing here uses; ssh's own defaults are what we run with.
        enableDefaultConfig = false;
        settings = sshHosts // {
          "*".WarnWeakCrypto = "no-pq-kex";
        };
      };

      home = {
        file.".ssh/config".force = true;
        packages = lib.mkIf onAndroid [ pkgs.openssh ];
      };

      stubbe.androidDaemons = lib.mkIf phoneSshd {
        sshd = "${lib.getExe' pkgs.openssh "sshd"} -D -e -f ${sshdConfig}";
      };

      stubbe.setup = {
        sshdHostKey = lib.mkIf phoneSshd {
          script = ''
            if [ ! -f ${lib.escapeShellArg sshdHostKey} ]; then
              install -d -m 0700 ${lib.escapeShellArg sshdDir}
              ${lib.getExe' pkgs.openssh "ssh-keygen"} -q -t ed25519 -N "" -f ${lib.escapeShellArg sshdHostKey}
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
