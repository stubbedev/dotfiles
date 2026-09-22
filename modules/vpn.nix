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
# What is left is provisioning: one NetworkManager profile per provider,
# written at activation from the sops-managed config so the gateway and
# username never enter the Nix store, and a resume hook that brings the
# tunnel back when it was up before the machine slept.
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

  # Watches login1's PrepareForSleep: records which tunnels were up on the
  # way down and brings exactly those back once the machine wakes. The
  # markers live in $XDG_RUNTIME_DIR, which is wiped on boot, so this can
  # never become a VPN that dials itself unattended.
  resumeWatch =
    { lib, pkgs }:
    pkgs.stubbe.bashApp {
      name = "vpn-resume-watch";
      runtimeInputs = [
        pkgs.dbus
        pkgs.networkmanager
      ];
      text = ''
        set -uo pipefail

        readonly PROVIDERS="${lib.concatStringsSep " " providers}"
        runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

        record() {
          for provider in $PROVIDERS; do
            if nmcli --terse --field NAME,TYPE connection show --active 2>/dev/null |
              awk -F: -v p="$provider" '$2 == "vpn" && $1 == p { found = 1 } END { exit !found }'
            then
              : > "$runtime/vpn-was-up-$provider"
            else
              rm -f "$runtime/vpn-was-up-$provider"
            fi
          done
        }

        restore() {
          for provider in $PROVIDERS; do
            [ -f "$runtime/vpn-was-up-$provider" ] || continue
            # NetworkManager may itself still be waking, and the wifi with
            # it: retry while the carrier settles rather than treat the
            # first refusal as final.
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              if nmcli connection up "$provider" >/dev/null 2>&1; then
                break
              fi
              sleep 3
            done
          done
        }

        dbus-monitor --system \
          "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
          while IFS= read -r line; do
            case "$line" in
              *boolean\ true*) record ;;
              *boolean\ false*) restore & ;;
            esac
          done
      '';
    };
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
    in
    lib.mkIf config.stubbe.userFeatures.vpn {
      systemd.services = lib.genAttrs (map unitOf providers) (
        name:
        let
          provider = lib.removePrefix "nm-vpn-profile-" name;
          configPath = configOf provider home;
        in
        {
          description = "Provision the ${provider} NetworkManager VPN profile";
          wantedBy = [ "multi-user.target" ];
          after = [ "NetworkManager.service" ];
          # Skip when the profile already exists: once written it is user
          # state, owned by NetworkManager and the wayle widget that edits
          # it, not something a switch gets to clobber.
          unitConfig.ConditionPathExists = [
            "!${profileTarget provider}"
            configPath
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.stubbe.shellScript "nm-vpn-profile-${provider}" ''
              set -euo pipefail

              keyfile_tmp=$(mktemp)
              trap 'rm -f "$keyfile_tmp"' EXIT

              # shellcheck source=/dev/null
              source "${configPath}"
              ${keyfileBody provider (uuidOf provider)}

              install -D -m 0600 -o root -g root "$keyfile_tmp" "${profileTarget provider}"
              ${lib.getExe' pkgs.networkmanager "nmcli"} connection reload >/dev/null 2>&1 || true
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
            enter the Nix store, and retires the pre-wayle machinery this aspect
            used to install: the root openconnect systemd unit, its
            /usr/local/sbin runner, and the polkit rule that allowed starting
            and stopping it. Credential caches keyed by profile UUIDs that
            no longer exist are dropped along the way.

            The profile is written only when absent; after that it is user
            state, owned by NetworkManager and the wayle widget that edits it.
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

                  if [ ! -e "${profileTarget provider}" ]; then
                  sudo install -D -m 0600 -o root -g root "$keyfile_tmp" "${profileTarget provider}"
                  fi
                  # NM's keyfile plugin does not watch the directory, and an
                  # unprivileged reload is refused by polkit: load it as root,
                  # on every run, so a profile written earlier but never picked
                  # up still gets registered.
                  sudo nmcli connection load "${profileTarget provider}"

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

      systemd.user.services.vpn-resume = lib.mkIf config.features.hyprland {
        Unit = {
          Description = "Restore VPN tunnels after suspend";
          After = [ "hyprland-session.target" ];
          PartOf = [ "hyprland-session.target" ];
        };
        Install.WantedBy = [ "hyprland-session.target" ];
        Service = {
          ExecStart = lib.getExe (resumeWatch {
            inherit lib pkgs;
          });
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
}
