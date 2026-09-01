# Auth stays interactive in the user session: GlobalProtect 2FA happens in
# `openconnect --authenticate` (unprivileged), the resulting session cookie is
# cached at ~/.config/vpn/<provider>/cookie (0600), and the root service reads
# it via systemd LoadCredential — the cookie never appears in argv or the
# journal. KillSignal=SIGKILL preserves the old SIGKILL-on-disconnect trick:
# openconnect skips its /ssl-vpn/logout.esp call, the gateway keeps the cookie
# valid until its idle-timeout, and a quick reconnect needs no fresh 2FA.
_:
let
  providers = [ "konform" ];

  unitOf = provider: "openconnect-${provider}.service";

  ifaceOf = provider: builtins.substring 0 15 "oc-${provider}";

  runScript =
    { openconnect, provider }:
    ''
      set -euo pipefail

      # shellcheck source=/dev/null
      source "$CREDENTIALS_DIRECTORY/config"
      # shellcheck source=/dev/null
      source "$CREDENTIALS_DIRECTORY/cookie"

      args=(
        --protocol=gp
        --user "$VPN_USERNAME"
        --cookie-on-stdin
        --interface ${ifaceOf provider}
      )
      usergroup="''${VPN_USERGROUP-gateway}"
      if [ -n "$usergroup" ]; then
        args+=(--usergroup="$usergroup")
      fi
      if [ -n "''${VPN_FINGERPRINT:-}" ]; then
        args+=(--servercert "$VPN_FINGERPRINT")
      fi

      exec ${openconnect} "''${args[@]}" "$VPN_HOST" <<<"$VPN_COOKIE"
    '';

  polkitRule =
    username:
    let
      units = builtins.toJSON (map unitOf providers);
    in
    ''
      // managed-by: stubbe vpn — systemctl start/stop for the openconnect units
      polkit.addRule(function (action, subject) {
        var units = ${units};
        if (
          action.id === "org.freedesktop.systemd1.manage-units" &&
          units.indexOf(action.lookup("unit")) !== -1 &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) !== -1 &&
          subject.user === "${username}" &&
          subject.local &&
          subject.active
        ) {
          return polkit.Result.YES;
        }
      });
    '';

  credentialsOf = provider: home: [
    "config:${home}/.config/vpn/${provider}/config"
    "cookie:${home}/.config/vpn/${provider}/cookie"
  ];
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
      systemd.services = lib.genAttrs (map (p: "openconnect-${p}") providers) (
        name:
        let
          provider = lib.removePrefix "openconnect-" name;
        in
        {
          description = "openconnect VPN tunnel (${provider})";
          serviceConfig = {
            Type = "exec";
            LoadCredential = credentialsOf provider home;
            ExecStart = pkgs.stubbe.shellScript "openconnect-${provider}-run" (runScript {
              openconnect = lib.getExe pkgs.openconnect;
              inherit provider;
            });
            KillSignal = "SIGKILL";
          };
        }
      );

      environment.etc."polkit-1/rules.d/49-openconnect.rules".text = polkitRule username;
    };

  flake.modules.homeManager.vpn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      mkScripts =
        provider:
        let
          unit = unitOf provider;
          iface = ifaceOf provider;
          # Every script probes the tunnel interface; the config-dir paths are
          # declared per script — shellcheck (SC2034) fails the build on an
          # unused variable, and not every script reads them all.
          common = ''
            interface_up() {
              local state
              [ -d "/sys/class/net/${iface}" ] || return 1
              state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || true)
              [ "$state" = "up" ] || [ "$state" = "unknown" ]
            }
          '';
        in
        lib.mapAttrsToList
          (
            action: text:
            pkgs.stubbe.bashApp {
              inherit text;
              name = "vpn-${provider}-${action}";
              runtimeInputs = [ pkgs.util-linux ];
            }
          )
          {
            connect = ''
              ${common}
              CONFIG_DIR="$HOME/.config/vpn/${provider}"
              CONFIG_FILE="$CONFIG_DIR/config"
              PASSWORD_FILE="$CONFIG_DIR/password"
              COOKIE_FILE="$CONFIG_DIR/cookie"
              LOG_FILE="/run/user/$(id -u)/openconnect-${provider}.log"

              if [ ! -f "$CONFIG_FILE" ]; then
                echo "Error: VPN config not found at $CONFIG_FILE" >&2
                echo "Run: hm secret edit vpn-${provider}-config && hm switch" >&2
                exit 1
              fi

              # shellcheck source=/dev/null
              source "$CONFIG_FILE"

              if [ -z "''${VPN_GATEWAY:-}" ] || [ -z "''${VPN_USERNAME:-}" ]; then
                echo "Error: $CONFIG_FILE missing VPN_GATEWAY or VPN_USERNAME" >&2
                exit 1
              fi

              if [ ! -f "$PASSWORD_FILE" ]; then
                echo "Error: Password file not found at $PASSWORD_FILE" >&2
                echo "Run: hm secret set vpn-${provider} && hm switch" >&2
                exit 1
              fi

              if systemctl is-active --quiet ${unit} && interface_up; then
                echo "${provider} VPN already running"
                exit 0
              fi

              unquote() {
                local v="$1"
                local esc="'\\'''"
                if [ "''${v#\'}" != "$v" ]; then
                  v="''${v#\'}"
                  v="''${v%\'}"
                  v="''${v//"$esc"/\'}"
                fi
                printf '%s' "$v"
              }

              load_cookie() {
                [ -f "$COOKIE_FILE" ] || return 1
                # shellcheck source=/dev/null
                source "$COOKIE_FILE"
                [ -n "''${VPN_COOKIE:-}" ] && [ -n "''${VPN_HOST:-}" ]
              }

              fetch_cookie() {
                local password="$1"
                local auth_output
                local usergroup="''${VPN_USERGROUP-gateway}"

                echo "Authenticating (2FA prompt expected)..." >&2

                auth_output=$(printf '%s\n' "$password" | openconnect \
                  --protocol=gp \
                  --user "$VPN_USERNAME" \
                  ''${usergroup:+--usergroup="$usergroup"} \
                  --passwd-on-stdin \
                  --authenticate \
                  "$VPN_GATEWAY" 2>>"$LOG_FILE") || true

                if [ -z "$auth_output" ]; then
                  echo "Authentication failed" >&2
                  return 1
                fi

                local COOKIE="" HOST="" FINGERPRINT="" key value
                while IFS='=' read -r key value; do
                  case "$key" in
                    COOKIE) COOKIE=$(unquote "$value") ;;
                    HOST) HOST=$(unquote "$value") ;;
                    FINGERPRINT) FINGERPRINT=$(unquote "$value") ;;
                  esac
                done < <(printf '%s\n' "$auth_output" | grep -E '^(COOKIE|HOST|FINGERPRINT)=' || true)

                if [ -z "$COOKIE" ] || [ -z "$HOST" ]; then
                  echo "Failed to parse authentication response" >&2
                  return 1
                fi

                mkdir -p "$CONFIG_DIR"
                ( umask 077
                  printf 'VPN_COOKIE=%q\nVPN_HOST=%q\nVPN_FINGERPRINT=%q\n' \
                    "$COOKIE" "$HOST" "$FINGERPRINT" > "$COOKIE_FILE" )
              }

              start_unit() {
                systemctl start ${unit} || return 1
                for _ in $(seq 1 30); do
                  if interface_up; then
                    return 0
                  fi
                  if ! systemctl is-active --quiet ${unit}; then
                    return 1
                  fi
                  sleep 0.5
                done
                return 1
              }

              if systemctl is-active --quiet ${unit}; then
                echo "${unit} running but ${iface} is down — restarting" >&2
                systemctl stop ${unit} || true
              fi

              if load_cookie; then
                echo "Trying cached cookie..." >&2
                if start_unit; then
                  echo "${provider} VPN connected"
                  exit 0
                fi
                echo "Cached cookie rejected, re-authenticating..." >&2
                systemctl stop ${unit} 2>/dev/null || true
                rm -f "$COOKIE_FILE"
              fi

              password=$(<"$PASSWORD_FILE")
              if [ -z "$password" ]; then
                echo "Password file $PASSWORD_FILE is empty" >&2
                exit 1
              fi

              fetch_cookie "$password"

              if ! start_unit; then
                echo "Failed to connect after authentication" >&2
                rm -f "$COOKIE_FILE"
                exit 1
              fi

              echo "${provider} VPN connected"
            '';

            disconnect = ''
              systemctl stop ${unit}
              echo "${provider} VPN disconnected"
            '';

            status = ''
              ${common}
              if systemctl is-active --quiet ${unit} && interface_up; then
                echo "${provider} VPN: Connected"
              else
                echo "${provider} VPN: Disconnected"
              fi
            '';

            bar = ''
              ${common}
              CONFIG_FILE="$HOME/.config/vpn/${provider}/config"
              PASSWORD_FILE="$HOME/.config/vpn/${provider}/password"
              RUNTIME_DIR="/run/user/$(id -u)"
              CONNECTING_FILE="$RUNTIME_DIR/openconnect-${provider}.connecting"
              LOG_FILE="$RUNTIME_DIR/openconnect-${provider}-bar.log"
              CONNECT_SCRIPT="vpn-${provider}-connect"
              DISCONNECT_SCRIPT="vpn-${provider}-disconnect"
              CONNECT_TIMEOUT=90

              killable() {
                case "''${1:-}" in
                  ''' | *[!0-9]*) return 1 ;;
                esac
                [ "$1" -gt 1 ]
              }

              load_config() {
                [ -f "$CONFIG_FILE" ] || return 1
                # shellcheck source=/dev/null
                source "$CONFIG_FILE"
                [ -n "''${VPN_GATEWAY:-}" ] && [ -n "''${VPN_USERNAME:-}" ]
              }

              is_running() {
                interface_up
              }

              connecting_active() {
                [ -f "$CONNECTING_FILE" ] || return 1

                local PID="" START=0
                # shellcheck source=/dev/null
                source "$CONNECTING_FILE" 2>/dev/null || {
                  rm -f "$CONNECTING_FILE"
                  return 1
                }

                if [ -z "$PID" ] || [ "$START" -eq 0 ]; then
                  rm -f "$CONNECTING_FILE"
                  return 1
                fi

                if [ ! -d "/proc/$PID" ]; then
                  rm -f "$CONNECTING_FILE"
                  return 1
                fi

                local now age
                now=$(date +%s)
                age=$(( now - START ))

                if (( age >= CONNECT_TIMEOUT )); then
                  if killable "$PID"; then
                    kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
                  fi
                  rm -f "$CONNECTING_FILE"
                  setsid "$DISCONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
                  disown
                  return 1
                fi

                return 0
              }

              status() {
                local text class tooltip

                if ! load_config; then
                  text="󰫜"
                  class="error"
                  tooltip="VPN config missing: $CONFIG_FILE"
                elif is_running; then
                  text="󰦝"
                  class="connected"
                  tooltip="${provider} VPN connected"
                  rm -f "$CONNECTING_FILE"
                elif connecting_active; then
                  text="󱦛"
                  class="connecting"
                  tooltip="${provider} VPN connecting..."
                else
                  text="󱦚"
                  class="disconnected"
                  tooltip="${provider} VPN disconnected"
                fi

                printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tooltip"
              }

              connect() {
                if ! load_config; then
                  echo "Missing VPN config at $CONFIG_FILE" >&2
                  exit 1
                fi

                if [ ! -f "$PASSWORD_FILE" ]; then
                  echo "Missing password file at $PASSWORD_FILE" >&2
                  exit 1
                fi

                rm -f "$CONNECTING_FILE"

                local now
                now=$(date +%s)

                printf 'PID=1\nSTART=%s\n' "$now" > "$CONNECTING_FILE"

                setsid bash -c '
                  marker="$1"
                  start="$2"
                  script="$3"
                  trap "rm -f \"$marker\"" EXIT
                  printf "PID=%s\nSTART=%s\n" "$$" "$start" > "$marker"
                  "$script"
                ' _ "$CONNECTING_FILE" "$now" "$CONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
                disown
              }

              disconnect() {
                if [ -f "$CONNECTING_FILE" ]; then
                  local PID="" START=0
                  # shellcheck source=/dev/null
                  source "$CONNECTING_FILE" 2>/dev/null || true
                  if killable "$PID"; then
                    kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
                  fi
                  rm -f "$CONNECTING_FILE"
                fi

                setsid "$DISCONNECT_SCRIPT" </dev/null >>"$LOG_FILE" 2>&1 &
                disown
              }

              toggle() {
                if is_running; then
                  disconnect
                elif connecting_active; then
                  disconnect
                else
                  connect
                fi
              }

              case "''${1:-status}" in
                status) status ;;
                connect) connect ;;
                disconnect) disconnect ;;
                toggle) toggle ;;
                *)
                  echo "Usage: $0 [status|connect|disconnect|toggle]" >&2
                  exit 1
                  ;;
              esac
            '';
          };
    in
    lib.mkIf config.features.vpn {
      sops.secrets = {
        vpn-konform-config = pkgs.stubbe.secret {
          name = "vpn-konform-config";
          path = "${config.home.homeDirectory}/.config/vpn/konform/config";
        };
        vpn-konform = pkgs.stubbe.secret {
          name = "vpn-konform";
          path = "${config.home.homeDirectory}/.config/vpn/konform/password";
        };
      };

      home.packages = lib.concatMap mkScripts providers ++ [ pkgs.openconnect ];

      # The runner is a real file in /usr/local/sbin: a store path in an /etc
      # unit would break on nix-collect-garbage.
      stubbe.setup.vpnUnits = {
        privileged = true;
        title = "Installing openconnect systemd units + polkit rule";
        body = ''
          Installs one openconnect-<provider>.service system unit per VPN
          provider, a runner for it under /usr/local/sbin, and a polkit rule
          letting ${config.home.username} start/stop exactly those units
          without a password.
        '';
        script =
          let
            perProvider = lib.concatMapStrings (
              provider:
              let
                runner = "/usr/local/sbin/openconnect-${provider}-run";
              in
              ''
                ${pkgs.stubbe.setup.text {
                  name = "openconnect-${provider}-run";
                  target = runner;
                  mode = "0755";
                  text =
                    "#!/usr/bin/env bash\n"
                    + runScript {
                      openconnect = "${config.home.profileDirectory}/bin/openconnect";
                      inherit provider;
                    };
                }}

                ${pkgs.stubbe.setup.text {
                  name = unitOf provider;
                  target = "/etc/systemd/system/${unitOf provider}";
                  text = pkgs.stubbe.gen.unitText {
                    Unit.Description = "openconnect VPN tunnel (${provider})";
                    Service = {
                      Type = "exec";
                      LoadCredential = credentialsOf provider config.home.homeDirectory;
                      ExecStart = runner;
                      KillSignal = "SIGKILL";
                    };
                  };
                }}
              ''
            ) providers;
          in
          ''
            ${perProvider}

            ${pkgs.stubbe.setup.polkitRule {
              source = pkgs.writeText "49-openconnect.rules" (polkitRule config.home.username);
              target = "/etc/polkit-1/rules.d/49-openconnect.rules";
            }}

            ${pkgs.stubbe.setup.reloadUnits}
          '';
      };
    };
}
