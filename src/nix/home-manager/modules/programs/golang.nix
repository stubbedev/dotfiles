_: {
  flake.modules.homeManager.programsGo =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    lib.mkIf config.features.development {
      programs.go = {
        enable = true;
        package = pkgs.go;
      };

      home.sessionVariables = {
        GOROOT = "${pkgs.go}/share/go";
      };
    };
}
