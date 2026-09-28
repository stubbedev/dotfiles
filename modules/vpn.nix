# The VPN is wayle's now. NetworkManager's openconnect plugin brings the
# tunnel up, and wayle — registered as NM's secret agent — performs the
# GlobalProtect sign-in itself: password and 2FA are asked in the network
# dropdown, and the session cookie plus password are cached under
# ~/.local/state/wayle/vpn keyed by the profile's NM UUID, so a reconnect
# after a dropped tunnel or a resume from suspend costs no second factor.
# That replaces this aspect's previous root openconnect unit, the polkit rule
# that let the user start/stop it, the connect/disconnect/status scripts, and
# the bar widget they fed.
#
# The profile is persistent (vpn.persistent), so NM keeps the tunnel through a suspend or a
# change of wifi and openconnect reconnects on the same session, instead of the
# plugin stopping it with the SIGINT that logs the gateway session off. That
# is what wayle's NetworkManager detach hook used to paper over; wayle no
# longer ships it, and non-NixOS hosts have it removed from /etc.
#
# What is left is provisioning: one NetworkManager profile per provider,
# written at activation from the sops-managed config so the gateway and
# username never enter the Nix store, and kept persistent after that. It stays
# system-wide: NM refuses to activate a user-owned (connection.permissions)
# profile of a plugin that does not declare supports-safe-private-file-access,
# and NetworkManager-openconnect does not.
_:
let
  providers = [ "konform" ];

  # The NM profile UUID, derived from the provider name so it is stable
  # across rebuilds without being tracked by hand. wayle keys its credential
  # cache by it; a gateway password that has since changed just means the
  # cached one is rejected once and re-typed.
  uuidOf =
    provider:
    let
      hash = builtins.hashString "sha256" "nm-vpn-${provider}";
      part = offset: length: builtins.substring offset length hash;
    in
    "${part 0 8}-${part 8 4}-4${part 13 3}-a${part 17 3}-${part 20 12}";

  unitOf = provider: "nm-vpn-profile-${provider}";

  profileTarget = provider: "/etc/NetworkManager/system-connections/${provider}.nmconnection";

  configOf = provider: home: "${home}/.config/vpn/${provider}/config";

  # The keyfile NetworkManager reads, written from the sourced VPN config.
  # `wayle-username` is wayle's own data key (the plugin has none for it);
  # the `*-flags=2` triple marks the plugin's minted secrets not-saved, so NM
  # always asks the agent — wayle — rather than a stored value.
  keyfileBody = provider: uuid: ''
    usergroup="''${VPN_USERGROUP-gateway}"
    {
      printf '%s\n' \
        '[connection]' \
        'id=${provider}' \
        'uuid=${uuid}' \
        'type=vpn' \
        'autoconnect=false'
      printf '%s\n' \
        '[vpn]' \
        'service-type=org.freedesktop.NetworkManager.openconnect' \
        'persistent=true' \
        "gateway=$VPN_GATEWAY" \
        'protocol=gp' \
        "wayle-username=$VPN_USERNAME"
      if [ -n "$usergroup" ]; then
        printf 'usergroup=%s\n' "$usergroup"
      fi
      printf '%s\n' \
        'enable_csd_trojan=no' \
        'cookie-flags=2' \
        'gateway-flags=2' \
        'gwcert-flags=2'
      printf '%s\n' \
        '[ipv4]' \
        'method=auto'
      printf '%s\n' \
        '[ipv6]' \
        'method=auto'
    } > "$keyfile_tmp"
  '';

  # Persistence, applied to a profile that already exists: written by this
  # aspect before it asked for it, or by hand. A permission list is cleared
  # too — v0.8.52 of wayle made profiles user-owned, which NM then refused to
  # activate. Everything else in it stays user state.
  persist = nmcli: uuid: ''
    ${nmcli} connection modify ${uuid} connection.permissions "" vpn.persistent yes
  '';

  # Where the retired detach hook and its NetworkManager.service drop-in were
  # installed on non-NixOS hosts.
  detachHookTarget = "/etc/NetworkManager/dispatcher.d/pre-down.d/90-wayle-openconnect-detach";

  detachDropInTarget = "/etc/systemd/system/NetworkManager.service.d/90-wayle-openconnect-detach.conf";
in
{
  flake.modules.nixos.vpn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      username = config.host.primaryUser;
      home = config.users.users.${username}.home;
      nmcli = lib.getExe' pkgs.networkmanager "nmcli";
    in
    lib.mkIf config.stubbe.userFeatures.vpn {
      systemd.services = lib.genAttrs (map unitOf providers) (
        name:
        let
          provider = lib.removePrefix "nm-vpn-profile-" name;
          configPath = configOf provider home;
          uuid = uuidOf provider;
        in
        {
          description = "Provision the ${provider} NetworkManager VPN profile";
          wantedBy = [ "multi-user.target" ];
          after = [ "NetworkManager.service" ];
          unitConfig.ConditionPathExists = configPath;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.stubbe.shellScript "nm-vpn-profile-${provider}" ''
              set -euo pipefail

              # Written only when it is missing: once written the profile is
              # user state, owned by NetworkManager and the wayle widget that
              # edits it, not something a switch gets to clobber.
              if [ ! -e "${profileTarget provider}" ]; then
                keyfile_tmp=$(mktemp)
                trap 'rm -f "$keyfile_tmp"' EXIT

                # shellcheck source=/dev/null
                source "${configPath}"
                ${keyfileBody provider uuid}

                install -D -m 0600 -o root -g root "$keyfile_tmp" "${profileTarget provider}"
                ${nmcli} connection reload >/dev/null 2>&1 || true
              fi

              ${persist nmcli uuid}
            '';
          };
        }
      );
    };

  flake.modules.homeManager.vpn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.vpn {
      sops.secrets.vpn-konform-config = pkgs.stubbe.secret {
        name = "vpn-konform-config.env";
        path = "${config.home.homeDirectory}/.config/vpn/konform/config";
      };

      stubbe.setup.vpnProfile =
        let
          home = config.home.homeDirectory;
        in
        {
          privileged = true;
          title = "Provisioning the NetworkManager VPN profile";
          body = ''
            Writes /etc/NetworkManager/system-connections/<provider>.nmconnection
            from the sops-decrypted VPN config, so the gateway and username never
            enter the Nix store, and makes it persistent, so NM keeps the tunnel
            through a suspend or a change of wifi instead of logging the gateway
            session off.

            Also retires what came before: the root openconnect systemd unit,
            its /usr/local/sbin runner, the polkit rule that allowed starting
            and stopping it, and wayle's old NetworkManager detach hook with its
            NetworkManager.service drop-in, which persistence replaces.
            Credential caches keyed by profile UUIDs that no longer exist are
            dropped along the way.

            The profile is written only when NetworkManager does not know it;
            after that it is user state, owned by NetworkManager and the wayle
            widget that edits it, and only its persistence is kept in line.
          '';
          script =
            let
              perProvider = lib.concatMapStrings (
                provider:
                let
                  uuid = uuidOf provider;
                  cfg = "${home}/.config/vpn/${provider}/config";
                in
                ''
                  ${pkgs.stubbe.setup.requirePath cfg}

                  keyfile_tmp=$(mktemp)
                  trap 'rm -f "$keyfile_tmp"' EXIT

                  # shellcheck source=/dev/null
                  source "${cfg}"
                  ${keyfileBody provider uuid}

                  # Asked of NM, not of the keyfile: on a netplan host (Ubuntu)
                  # NM moves a profile it saves into /etc/netplan and deletes
                  # the keyfile, so "no keyfile" does not mean "no profile".
                  # Rewriting and loading it then replaced the live profile
                  # with this bare one on the next run of this step.
                  if ! nmcli -g connection.uuid connection show ${uuid} >/dev/null 2>&1; then
                  if [ ! -e "${profileTarget provider}" ]; then
                  sudo install -D -m 0600 -o root -g root "$keyfile_tmp" "${profileTarget provider}"
                  fi
                  # NM's keyfile plugin does not watch the directory, and an
                  # unprivileged reload is refused by polkit: load it as root,
                  # so a profile written earlier but never picked up still
                  # gets registered.
                  sudo nmcli connection load "${profileTarget provider}"
                  fi

                  # Through NM rather than the file, for the same netplan reason.
                  ${persist "sudo nmcli" uuid}

                  sudo systemctl disable --now openconnect-${provider}.service >/dev/null 2>&1 || true
                  sudo rm -f \
                  /etc/systemd/system/openconnect-${provider}.service \
                  /usr/local/sbin/openconnect-${provider}-run
                ''
              ) providers;
              keepCaches =
                extension: lib.concatMapStrings (provider: " ! -name '${uuidOf provider}.${extension}'") providers;
            in
            ''
              PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

              ${perProvider}

              # The detach hook and its drop-in, from before persistence made
              # them unnecessary. The drop-in is an ExecStop= of
              # NetworkManager.service, so the daemon-reload below matters.
              sudo rm -f ${detachHookTarget} ${detachDropInTarget}

              # Credential caches keyed by NM profile UUIDs that no longer
              # exist — the pre-migration pair above all, whose password the
              # gateway has since changed. Caches for live profiles are kept:
              # they are what makes a reconnect cost no second factor.
              state_dir="${home}/.local/state/wayle/vpn"
              if [ -d "$state_dir" ]; then
              find "$state_dir" -maxdepth 1 -type f -name '*.cookie'${keepCaches "cookie"} -delete
              find "$state_dir" -maxdepth 1 -type f -name '*.password'${keepCaches "password"} -delete
              fi

              sudo rm -f /etc/polkit-1/rules.d/49-openconnect.rules
              ${pkgs.stubbe.setup.reloadUnits}
            '';
        };
    };
}
