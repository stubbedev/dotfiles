# Keeps the avahi-discovered .local host cache warm for ssh-style
# completion. avahi-browse takes ~1.5s, so the shell never runs it —
# _avahi_ssh_hosts in src/zsh/settings only reads the cache file this
# timer maintains. The service-type filter excludes Sonos boxes,
# printers, etc. so only ssh-able machines show up.
_: {
  flake.modules.homeManager.zshAvahiHosts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cacheFile = "${config.xdg.cacheHome}/zsh-avahi-hosts";
      refreshScript = pkgs.writeShellScript "zsh-avahi-hosts-refresh" ''
        set -u
        mkdir -p "$(dirname '${cacheFile}')"
        tmp='${cacheFile}.tmp'
        # avahi-browse talks to the system avahi-daemon over D-Bus; if the
        # host runs no daemon this fails and we keep the old cache.
        if ${pkgs.avahi}/bin/avahi-browse -atrp 2>/dev/null \
             | ${pkgs.gawk}/bin/awk -F';' '$1=="=" && $3=="IPv4" && ($5=="_workstation._tcp" || $5 ~ /ssh/) && $7!="" {print $7}' \
             | sort -u > "$tmp" 2>/dev/null; then
          mv "$tmp" '${cacheFile}'
        else
          rm -f "$tmp"
        fi
      '';
    in
    lib.mkIf config.features.desktop {
      systemd.user.services.zsh-avahi-hosts = {
        Unit = {
          Description = "Refresh avahi .local host cache for zsh completion";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${refreshScript}";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.zsh-avahi-hosts = {
        Unit = {
          Description = "Periodic avahi host cache refresh";
        };
        Timer = {
          # LAN host set is near-static, so a slow poll keeps the cache
          # fresh enough for completion without waking every minute.
          OnBootSec = "30s";
          OnUnitActiveSec = "10min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
}
