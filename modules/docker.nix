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
          # registry:3 = distribution v3: same on-disk layout as v2, non-root
          # by default. Major tag, not :latest, so a v4 can't surprise us.
          image = "registry:3";
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
      # Client tooling from nix: pinned by flake.lock, same on every host.
      # The ENGINE is a host prerequisite (root daemon, distro unit) — the
      # setup below requires it and tells you how to get it, rather than
      # guessing a package manager.
      home.packages = [
        pkgs.docker
        pkgs.docker-compose
      ];

      stubbe.setup.docker = lib.mkIf config.features.docker {
        privileged = true;
        title = "Configuring Docker";
        body = ''
          Requires the docker engine already installed and running (host
          prerequisite; the script fails with the exact install command if
          not). Adds ${config.home.username} to the docker group so non-root
          containers work without sudo, merges required keys into
          /etc/docker/daemon.json (features.containerd-snapshotter, log
          rotation, insecure-registries for localhost:5000; drops legacy
          storage-driver), and starts a local registry:3 container on :5000
          backed by the registry-data volume. Client tooling (docker,
          docker-compose) comes from nix.
        '';
        script = ''
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          if ! sudo systemctl is-active --quiet docker.service 2>/dev/null; then
            echo "docker engine not running on this host - install it first:" >&2
            echo "  arch/endeavouros: sudo pacman -S docker docker-compose docker-buildx && sudo systemctl enable --now docker" >&2
            echo "  fedora:           sudo dnf install -y docker && sudo systemctl enable --now docker" >&2
            echo "  debian/ubuntu:    curl -fsSL https://get.docker.com | sudo sh" >&2
            exit 1
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
            sudo systemctl restart docker.service >/dev/null 2>&1 || true
          fi
          rm -f "$_stb_current" "$_stb_new"

          _stb_running=$(sudo docker inspect registry --format '{{.Config.Image}}' 2>/dev/null || true)
          if [ "$_stb_running" != "registry:3" ]; then
            # Missing, or still the legacy v2 container: (re)create. The
            # registry-data volume carries over - v3 reads the v2 layout.
            [ -n "$_stb_running" ] && sudo docker rm -f registry >/dev/null 2>&1
            sudo docker run -d \
              --name registry \
              --restart=always \
              -p 5000:5000 \
              -v registry-data:/var/lib/registry \
              registry:3 >/dev/null
          fi
        '';
      };
    };
}
