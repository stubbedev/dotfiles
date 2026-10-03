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
    let
      # Engine units rendered from nix, mirroring NixOS's
      # virtualisation.docker module (nixpkgs#90055d5e): socket activation
      # with SocketGroup=docker (0660 — group members reach the daemon without
      # any daemon-side group setting), Type=notify, live-restore so daemon
      # restarts don't kill containers. dockerd/containerd/runc come from the
      # same locked rev as the client; iptables and kmod ride the unit's PATH
      # (modprobe for bridge/overlay, iptables for the bridge firewall).
      # /etc/systemd/system shadows any distro unit; /var/lib/docker state
      # carries over across upgrades.
      engineDockerService = pkgs.stubbe.gen.systemd "docker.service" {
        Unit = {
          Description = "Docker Engine (nix-provisioned)";
          After = [
            "network-online.target"
            "docker.socket"
          ];
          Wants = [ "network-online.target" ];
          Requires = [ "docker.socket" ];
        };
        Service = {
          Type = "notify";
          Environment = "PATH=${pkgs.iptables}/bin:${pkgs.iptables}/sbin:${pkgs.kmod}/bin:/usr/sbin:/usr/bin:/sbin:/bin";
          ExecStart = "${pkgs.docker}/bin/dockerd";
          ExecReload = "kill -s HUP \$MAINPID";
          LimitNOFILE = 1048576;
          Delegate = "yes";
          KillMode = "process";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "multi-user.target" ];
      };
      engineDockerSocket = pkgs.stubbe.gen.systemd "docker.socket" {
        Unit.Description = "Docker Socket for the API";
        Socket = {
          ListenStream = "/run/docker.sock";
          SocketMode = "0660";
          SocketUser = "root";
          SocketGroup = "docker";
        };
        Install.WantedBy = [ "sockets.target" ];
      };
    in
    {
      # Client from nix, same rev as the engine unit above.
      home.packages = [
        pkgs.docker
        pkgs.docker-compose
      ];

      stubbe.setup.docker = lib.mkIf config.features.docker {
        privileged = true;
        title = "Installing Docker";
        body = ''
          Provisions the docker engine from nix (no distro package manager):
          renders /etc/systemd/system/docker.service pointing at the locked
          dockerd/containerd/runc, enables and starts it, adds
          ${config.home.username} to the docker group so non-root containers
          work without sudo, merges required keys into /etc/docker/daemon.json
          (features.containerd-snapshotter, log rotation, insecure-registries
          for localhost:5000; drops legacy storage-driver), and starts a local
          registry:3 container on :5000 backed by the registry-data volume.
        '';
        script = ''
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          # Group first: the socket unit's SocketGroup needs it to exist.
          sudo groupadd -f docker
          if ! id -nG ${config.home.username} | tr ' ' '\n' | grep -qx docker; then
            sudo usermod -aG docker ${config.home.username}
            echo "Added ${config.home.username} to the docker group; log out and back in for it to take effect."
          fi

          # Engine: render-and-cmp, so re-runs and lock bumps are the only
          # things that touch the unit files.
          _stb_changed=0
          for pair in \
            "${engineDockerService}:/etc/systemd/system/docker.service" \
            "${engineDockerSocket}:/etc/systemd/system/docker.socket"; do
            _stb_src="''${pair%%:*}"
            _stb_dst="''${pair#*:}"
            if ! sudo cmp -s "$_stb_src" "$_stb_dst" 2>/dev/null; then
              sudo install -m 0644 "$_stb_src" "$_stb_dst"
              _stb_changed=1
            fi
          done
          if [ "$_stb_changed" = 1 ]; then
            sudo systemctl daemon-reload
            sudo systemctl enable --now docker.socket docker.service >/dev/null 2>&1 || true
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
              live-restore = true;
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
            # First-install case: wait for the fresh daemon to accept
            # connections before talking to it.
            _stb_wait=0
            until sudo docker info >/dev/null 2>&1; do
              [ "$_stb_wait" -ge 20 ] && echo "docker daemon did not come up" >&2 && exit 1
              sleep 1
              _stb_wait=$((_stb_wait + 1))
            done
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
