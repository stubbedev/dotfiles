_: {
  enableIf = { config, ... }: config.features.docker;
  args =
    {
      config,
      pkgs,
      homeLib,
      ...
    }:
    homeLib.mkInstallPrompt {
      subject = "Docker";
      body = ''
        Install Docker (engine + compose) via the host's package manager,
        enable the docker.service systemd unit, add ${config.home.username}
        to the docker group so non-root containers work without sudo,
        merge required keys into /etc/docker/daemon.json
        (features.containerd-snapshotter, insecure-registries for
        localhost:5000; drops legacy storage-driver), and start a local
        registry:2 container on :5000 backed by the registry-data volume.

        On NixOS, set virtualisation.docker.enable = true in the system
        config instead — this activation is gated off there.
      '';
      actionScript = ''
        # Activation scripts run with a stripped PATH; bring the standard
        # system paths back so command -v can find dnf/apt-get/pacman.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        if ! command -v docker >/dev/null 2>&1; then
          if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
          elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y docker docker-compose
          elif command -v apt-get >/dev/null 2>&1; then
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' RETURN
            curl -fsSL https://get.docker.com -o "$tmp/get-docker.sh"
            sudo sh "$tmp/get-docker.sh"
          else
            echo "No supported package manager (pacman/dnf/apt-get) found." >&2
            exit 1
          fi
        fi

        # Idempotent group + membership setup. groupadd -f is a no-op if it
        # exists; the id check avoids a redundant usermod (and the resulting
        # journal log line) on every activation.
        sudo groupadd -f docker
        if ! id -nG ${config.home.username} | tr ' ' '\n' | grep -qx docker; then
          sudo usermod -aG docker ${config.home.username}
          echo "Added ${config.home.username} to the docker group; log out and back in for it to take effect."
        fi

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl enable --now docker.service >/dev/null 2>&1 || true
        fi

        # Merge required keys into /etc/docker/daemon.json without
        # clobbering anything the user added by hand (DNS, log-opts, ...).
        # containerd-snapshotter unlocks multi-arch image handling; the
        # insecure-registries entry lets `docker push localhost:5000/...`
        # use plain HTTP. storage-driver is stripped because it conflicts
        # with containerd-snapshotter.
        _stb_daemon_patch=$(mktemp)
        cat > "$_stb_daemon_patch" <<'EOF'
        {
          "features": { "containerd-snapshotter": true },
          "insecure-registries": ["localhost:5000"]
        }
        EOF

        sudo mkdir -p /etc/docker
        _stb_daemon_current=$(mktemp)
        if sudo test -f /etc/docker/daemon.json; then
          sudo cat /etc/docker/daemon.json > "$_stb_daemon_current"
        else
          echo '{}' > "$_stb_daemon_current"
        fi

        _stb_daemon_new=$(mktemp)
        ${pkgs.jq}/bin/jq -s '
          (.[0] // {}) * .[1]
          | del(."storage-driver")
        ' "$_stb_daemon_current" "$_stb_daemon_patch" > "$_stb_daemon_new"

        if ! sudo test -f /etc/docker/daemon.json || \
           ! sudo cmp -s "$_stb_daemon_new" /etc/docker/daemon.json; then
          sudo install -m 0644 -o root -g root "$_stb_daemon_new" /etc/docker/daemon.json
          if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl restart docker.service >/dev/null 2>&1 || true
          fi
        fi
        rm -f "$_stb_daemon_patch" "$_stb_daemon_current" "$_stb_daemon_new"

        # Local registry container. Idempotent: only `docker run` when no
        # container named `registry` exists; existing ones (running or
        # stopped) are left alone so we don't churn or wipe in-flight
        # image blobs on every activation.
        if ! sudo docker inspect registry >/dev/null 2>&1; then
          sudo docker run -d \
            --name registry \
            --restart=always \
            -p 5000:5000 \
            -v registry-data:/var/lib/registry \
            registry:2 >/dev/null
        fi
      '';
    };
}
