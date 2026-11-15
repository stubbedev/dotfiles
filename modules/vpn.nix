# The VPN is lys-shell's now. NetworkManager's openconnect plugin brings the
# tunnel up, and lys-shell — registered as NM's secret agent — performs the
# GlobalProtect sign-in itself: password and 2FA are asked in the network
# dropdown, and the session cookie plus password are cached under
# ~/.local/state/lys-shell/vpn keyed by the profile's NM UUID, so a reconnect
# after a dropped tunnel or a resume from suspend costs no second factor.
# That replaces this aspect's previous root openconnect unit, the polkit rule
# that let the user start/stop it, the connect/disconnect/status scripts, and
# the bar widget they fed.
#
# The profile is persistent (vpn.persistent), so NM keeps the tunnel through a suspend or a
# change of wifi and openconnect reconnects on the same session, instead of the
# plugin stopping it with the SIGINT that logs the gateway session off.
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
  # across rebuilds without being tracked by hand. lys-shell keys its credential
  # cache by it; a gateway password that has since changed just means the
  # cached one is rejected once and re-typed.
  uuidOf =
    provider:
    let
      hash = builtins.hashString "sha256" "nm-vpn-${provider}";
      part = offset: length: builtins.substring offset length hash;
    in
    "${part 0 8}-${part 8 4}-4${part 13 3}-a${part 17 3}-${part 20 12}";

  profileTarget = provider: "/etc/NetworkManager/system-connections/${provider}.nmconnection";

  configOf = provider: home: "${home}/.config/vpn/${provider}/config";

  # The keyfile NetworkManager reads, written from the sourced VPN config.
  # `lys-shell-username` is lys-shell's own data key (the plugin has none for it);
  # the `*-flags=2` triple marks the plugin's minted secrets not-saved, so NM
  # always asks the agent — lys-shell — rather than a stored value.
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
        "lys-shell-username=$VPN_USERNAME"
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
  # too: NM refuses to activate a user-owned profile of this plugin.
  # Everything else in it stays user state.
  persist = nmcli: uuid: ''
    ${nmcli} connection modify ${uuid} connection.permissions "" vpn.persistent yes
  '';
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
      systemd.services = lib.listToAttrs (
        map (
          provider:
          let
            configPath = configOf provider home;
            uuid = uuidOf provider;
          in
          lib.nameValuePair "nm-vpn-profile-${provider}" {
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
                # user state, owned by NetworkManager and the lys-shell widget that
                # edits it, not something a switch gets to clobber.
                if [ ! -e "${profileTarget provider}" ]; then
                  keyfile_tmp=$(mktemp)
                  trap 'rm -f "$keyfile_tmp"' EXIT

                  # shellcheck source=/dev/null
                  source "${configPath}"
                  ${keyfileBody provider uuid}

                  install -D -m 0600 -o root -g root "$keyfile_tmp" "${profileTarget provider}"
                  ${nmcli} connection load "${profileTarget provider}"
                fi

                ${persist nmcli uuid}
              '';
            };
          }
        ) providers
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
      sops.secrets = lib.listToAttrs (
        map (
          provider:
          lib.nameValuePair "vpn-${provider}-config" (
            pkgs.stubbe.secret {
              name = "vpn-${provider}-config.env";
              path = configOf provider config.home.homeDirectory;
            }
          )
        ) providers
      );
    };
}
