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
        minikube
      ];
    };
}
