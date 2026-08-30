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
        (lib.lowPrio minikube)
      ];
    };
}
