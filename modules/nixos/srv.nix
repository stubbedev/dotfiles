_: {
  flake.modules.nixos.srv =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      userHome = config.users.users.${config.host.primaryUser}.home;
      domainsFile = "${userHome}/.config/srv/traefik/local-domains.txt";
    in
    lib.mkIf (hmFeatures.srv or false) {
      # Hand DNS to systemd-resolved so split-DNS layers cleanly on top
      # of whatever per-link nameservers NetworkManager negotiates
      # (corp, VPN, ISP). srv_dns answers only the names srv has
      # registered; everything else stays on the link's upstream.
      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";

      # Whenever srv writes its domain list, regenerate the resolved
      # drop-in so adds/removes take effect without a nix-rebuild. Also
      # runs at boot so already-registered sites work after a reboot.
      systemd.paths.srv-resolved-sync = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = domainsFile;
          Unit = "srv-resolved-sync.service";
        };
      };

      systemd.services.srv-resolved-sync = {
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-resolved.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          src=${domainsFile}
          out=/etc/systemd/resolved.conf.d/srv.conf
          mkdir -p /etc/systemd/resolved.conf.d
          domains=""
          if [ -r "$src" ]; then
            while IFS= read -r name || [ -n "$name" ]; do
              [ -n "$name" ] || continue
              case "$name" in \#*) continue ;; esac
              domains="$domains ~$name"
            done < "$src"
          fi
          if [ -n "$domains" ]; then
            printf '[Resolve]\nDNS=127.0.0.1\nDomains=%s\n' "$domains" > "$out"
          else
            rm -f "$out"
          fi
          # Reload only if resolved is up — on boot the .service ordering
          # handles this, but during an early hm-switch resolved may not
          # yet be active and we don't want a transient failure to mark
          # the unit failed; the drop-in is on disk either way.
          if systemctl is-active --quiet systemd-resolved.service; then
            systemctl reload systemd-resolved.service || true
          fi
        '';
      };
    };
}
