_: {
  enableIf = { config, ... }: config.features.avahi;
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "Avahi (mDNS)";
      body = ''
        Install avahi-daemon + libnss-mdns via the host's package manager,
        write a managed /etc/avahi/avahi-daemon.conf that whitelists real
        LAN interfaces (excluding docker/veth/bridge), and enable the
        service so this host can resolve and be resolved as
        <hostname>.local on the LAN.

        On NixOS, services.avahi handles this; this activation is gated
        off there.
      '';
      actionScript = ''
        # Activations run with a stripped PATH; restore it so command -v
        # finds apt-get / dnf / pacman / ip under /usr/sbin etc.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        if ! command -v avahi-daemon >/dev/null 2>&1; then
          if command -v apt-get >/dev/null 2>&1; then
            # On Debian/Ubuntu, libnss-mdns's postinst edits
            # /etc/nsswitch.conf for us; the nsswitch step below is a
            # safety net (idempotent grep skips if already done).
            sudo apt-get update
            sudo apt-get install -y avahi-daemon libnss-mdns
          elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y avahi nss-mdns
          elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm avahi nss-mdns
          else
            echo "No supported package manager (apt-get/dnf/pacman) found." >&2
            exit 1
          fi
        fi

        # Ensure /etc/nsswitch.conf carries an mdns entry so `ssh foo.local`
        # resolves. Fedora's nss-mdns and Arch's nss-mdns ship the NSS
        # plugin but don't auto-edit nsswitch.conf — only Debian's
        # libnss-mdns does. Idempotent: skips when any mdns variant is
        # already in the hosts: line (including Debian's prior edit).
        #
        # Placement matters: must come BEFORE any `resolve` entry,
        # because Arch's default uses `resolve [!UNAVAIL=return]` which
        # swallows NOTFOUND for .local before mdns_minimal can run. We
        # insert right before `resolve` if present, else before `dns`,
        # else at the start of the entry list.
        if [ -f /etc/nsswitch.conf ] && \
           ! grep -qE '^hosts:[^#]*\bmdns[46]?(_minimal)?\b' /etc/nsswitch.conf; then
          # Only back up the first time; otherwise a partial-failure
          # retry would clobber the pristine backup with a half-edited
          # current state.
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

        # Whitelist real LAN NICs only. Without this, avahi advertises on
        # docker0 / br-* / veth* / VPN / k8s overlays too, collides the
        # hostname with itself across bridges (stubbe-laptop-2, -3, …),
        # and leaks it into container networks. `ip -br link` prints
        # names like `vethXYZ@if3`, so split on @ to get bare names.
        #
        # Captured at activation time; the script's lockfile (hashed on
        # script text, not output) means this won't re-detect new NICs
        # on its own. To refresh, delete
        # ~/.local/state/nix/home-manager/privileged-setup-avahi.lock.sum
        # and re-run `hm switch`.
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
          cat > "$_stb_tmp" <<EOF
        # Managed by stubbedev dotfiles —
        # modules/activation/_privileged/setup-avahi.nix
        [server]
        allow-interfaces=$ifaces
        use-ipv4=yes
        use-ipv6=yes
        ratelimit-interval-usec=1000000
        ratelimit-burst=1000

        [publish]
        publish-addresses=yes
        publish-hinfo=yes
        publish-workstation=yes
        publish-domain=yes

        [reflector]

        [rlimits]
        EOF
          sudo install -m 0644 -o root -g root "$_stb_tmp" /etc/avahi/avahi-daemon.conf
          rm -f "$_stb_tmp"
        fi

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl enable avahi-daemon.service >/dev/null 2>&1 || true
          sudo systemctl restart avahi-daemon.service >/dev/null 2>&1 || true
        fi
      '';
    };
}
