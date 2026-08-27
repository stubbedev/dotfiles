# Kubernetes CLI tooling.
_: {
  flake.modules.homeManager.k8s =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.k8s {
      home.packages = with pkgs; [
        kubectl
        kubectl.convert
        # minikube bundles its own bin/kubectl, which collides with the
        # standalone kubectl above in buildEnv. lowPrio makes minikube lose that
        # one file so the explicit kubectl wins; both tools stay installed.
        (lib.lowPrio minikube)
      ];
    };
}
