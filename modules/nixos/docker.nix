_: {
  flake.modules.nixos.docker =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.docker or false) {
      virtualisation.docker = {
        enable = true;

        # containerd-snapshotter unlocks multi-arch/OCI image support and
        # is required by buildx/compose workflows that pull from the local
        # registry below. insecure-registries lets `docker push
        # localhost:5000/...` go over plain HTTP — fine for a host-local
        # registry, would be unsafe over the network.
        daemon.settings = {
          features.containerd-snapshotter = true;
          insecure-registries = [ "localhost:5000" ];
        };
      };

      # Local Docker registry on :5000, backed by a named volume so image
      # blobs survive container restarts. Mirrors the manual `docker run`
      # used on non-NixOS hosts in setup-docker.nix.
      virtualisation.oci-containers = {
        backend = "docker";
        containers.registry = {
          image = "registry:2";
          ports = [ "5000:5000" ];
          volumes = [ "registry-data:/var/lib/registry" ];
          autoStart = true;
        };
      };

      # Replaces the user-group-add step from the non-NixOS
      # modules/activation/_privileged/setup-docker.nix activation script.
      users.users.${config.host.primaryUser}.extraGroups = [ "docker" ];
    };
}
