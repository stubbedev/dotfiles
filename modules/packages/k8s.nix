_: {
  flake.modules.homeManager.k8s =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.k8s {
      home.packages = with pkgs; [
        kubectl
        kubectl.convert
        # minikube bundles its own bin/kubectl, which collides with the
        # standalone kubectl above in buildEnv. lowPrio makes minikube lose
        # that one file so the explicit kubectl wins; both tools stay.
        (lib.lowPrio minikube)
      ];
    };
}
