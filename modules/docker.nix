let
  # registry:3 = distribution v3: same on-disk layout as v2, non-root by
  # default. Major tag, not :latest, so a v4 can't surprise us.
  registry = {
    image = "registry:3";
    port = 5000;
    volume = "registry-data:/var/lib/registry";
  };

  registryPublish = "${toString registry.port}:${toString registry.port}";
  registryHost = "localhost:${toString registry.port}";

  daemonSettings = {
    features.containerd-snapshotter = true;
    insecure-registries = [ registryHost ];

    # Unrotated json-file logs are unbounded: a single chatty container once
    # left a 21G log behind. Cap them.
    log-driver = "json-file";
    log-opts = {
      max-size = "50m";
      max-file = "3";
    };

    builder.gc = {
      enabled = true;
      defaultMaxUsedSpace = "30GB";
      defaultMinFreeSpace = "50GB";
    };
  };
in
{
  flake.modules.nixos.docker =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.docker {
      virtualisation.docker = {
        enable = true;
        daemon.settings = daemonSettings;
        extraPackages = [ pkgs.openssh ];
      };

      virtualisation.oci-containers = {
        backend = "docker";
        containers.registry = {
          inherit (registry) image;
          ports = [ registryPublish ];
          volumes = [ registry.volume ];
          autoStart = true;
        };
      };

      systemd.services.${config.virtualisation.oci-containers.containers.registry.serviceName} = {
        bindsTo = [ "docker.service" ];
        wantedBy = [ "docker.service" ];
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
      # Gated on the feature, so a host that has no engine (Android: no
      # socket, no systemd) does not get a client that can only talk to a
      # daemon it cannot run.
      home.packages = lib.mkIf config.features.docker [
        pkgs.docker
        pkgs.docker-compose
        pkgs.lazydocker
      ];

      systemd.user = lib.mkIf config.features.docker {
        services.docker-image-prune = {
          Unit.Description = "Remove Docker images no container uses that are over a week old";
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.docker} image prune --all --force --filter until=168h";
          };
        };
        timers.docker-image-prune = {
          Unit.Description = "Weekly removal of unused Docker images";
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
