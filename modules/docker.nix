_: {
  flake.modules.nixos.docker =
    { config, lib, ... }:
    lib.mkIf config.stubbe.userFeatures.docker {
      virtualisation.docker = {
        enable = true;

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

          sudo groupadd -f docker
          if ! id -nG ${config.home.username} | tr ' ' '\n' | grep -qx docker; then
            sudo usermod -aG docker ${config.home.username}
            echo "Added ${config.home.username} to the docker group; log out and back in for it to take effect."
          fi

          if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl enable --now docker.service >/dev/null 2>&1 || true
          fi

          _stb_patch=${
            pkgs.stubbe.gen.json "docker-daemon-patch.json" {
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
            # shellcheck disable=SC2024 # sudo is for reading the root-only file;
            # the redirect target is our own mktemp, written as us.
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
