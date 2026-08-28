# Docker, plus the host-local registry on :5000 that the build workflows push
# to. Both halves configure the same daemon settings, so the containerd
# snapshotter and the insecure-registry entry cannot drift.
_: {
  flake.modules.nixos.docker =
    { config, lib, ... }:
    lib.mkIf config.stubbe.userFeatures.docker {
      virtualisation.docker = {
        enable = true;

        # containerd-snapshotter unlocks multi-arch/OCI image support and is
        # required by the buildx/compose workflows that pull from the local
        # registry below. insecure-registries lets `docker push
        # localhost:5000/...` go over plain HTTP — fine for a host-local
        # registry, unsafe over the network.
        daemon.settings = {
          features.containerd-snapshotter = true;
          insecure-registries = [ "localhost:5000" ];

          # Unrotated json-file logs are unbounded: a single chatty container
          # once left a 21G log behind. Cap them.
          log-driver = "json-file";
          log-opts = {
            max-size = "50m";
            max-file = "3";
          };
        };
      };

      # Local registry, backed by a named volume so image blobs survive
      # container restarts.
      virtualisation.oci-containers = {
        backend = "docker";
        containers.registry = {
          image = "registry:2";
          ports = [ "5000:5000" ];
          volumes = [ "registry-data:/var/lib/registry" ];
          autoStart = true;
        };
      };

      users.users.${config.host.primaryUser}.extraGroups = [ "docker" ];
    };

  flake.modules.homeManager.docker =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stubbe.setup.docker = lib.mkIf config.features.docker {
        privileged = true;
        title = "Installing Docker";
        body = ''
          Install Docker (engine + compose) via the host's package manager,
          enable the docker.service systemd unit, add ${config.home.username}
          to the docker group so non-root containers work without sudo,
          merge required keys into /etc/docker/daemon.json
          (features.containerd-snapshotter, log rotation, insecure-registries for
          localhost:5000; drops legacy storage-driver), and start a local
          registry:2 container on :5000 backed by the registry-data volume.
        '';
        script = ''
          # Activations run with a stripped PATH; bring the standard system
          # paths back so `command -v` can find dnf/apt-get/pacman.
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          # Not installHostPackage: Debian/Ubuntu's distro docker.io lags badly
          # and lacks compose v2, so use Docker's own convenience script there.
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

          # Idempotent group + membership. `groupadd -f` is a no-op when the
          # group exists; the id check avoids a redundant usermod (and its
          # journal line) on every activation.
          sudo groupadd -f docker
          if ! id -nG ${config.home.username} | tr ' ' '\n' | grep -qx docker; then
            sudo usermod -aG docker ${config.home.username}
            echo "Added ${config.home.username} to the docker group; log out and back in for it to take effect."
          fi

          if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl enable --now docker.service >/dev/null 2>&1 || true
          fi

          # Merge required keys into /etc/docker/daemon.json without clobbering
          # anything added by hand (DNS, registry-mirrors, …). storage-driver is
          # stripped because it conflicts with containerd-snapshotter. Same
          # settings as virtualisation.docker.daemon.settings above.
          _stb_patch=${
            (pkgs.formats.json { }).generate "docker-daemon-patch.json" {
              features.containerd-snapshotter = true;
              insecure-registries = [ "localhost:5000" ];
              log-driver = "json-file";
              log-opts = {
                max-size = "50m";
                max-file = "3";
              };
            }
          }

          sudo mkdir -p /etc/docker
          _stb_current=$(mktemp)
          if sudo test -f /etc/docker/daemon.json; then
            sudo cat /etc/docker/daemon.json > "$_stb_current"
          else
            echo '{}' > "$_stb_current"
          fi

          _stb_new=$(mktemp)
          ${lib.getExe pkgs.jq} -s '
            (.[0] // {}) * .[1]
            | del(."storage-driver")
          ' "$_stb_current" "$_stb_patch" > "$_stb_new"

          if ! sudo test -f /etc/docker/daemon.json || \
             ! sudo cmp -s "$_stb_new" /etc/docker/daemon.json; then
            sudo install -m 0644 -o root -g root "$_stb_new" /etc/docker/daemon.json
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl restart docker.service >/dev/null 2>&1 || true
            fi
          fi
          rm -f "$_stb_current" "$_stb_new"

          # Local registry container. Idempotent: only `docker run` when no
          # container named `registry` exists; existing ones (running or
          # stopped) are left alone so we do not churn or wipe in-flight image
          # blobs on every activation.
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
    };
}
