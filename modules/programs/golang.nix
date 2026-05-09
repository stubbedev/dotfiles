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
        # Relocate default ~/go to ~/.go so $HOME stays clean. GOBIN unset →
        # defaults to $GOPATH/bin, which paths.zsh deliberately keeps off
        # PATH so `go install` doesn't shadow nix-pinned tooling.
        env.GOPATH = "${config.home.homeDirectory}/.go";
      };

      home.sessionVariables = {
        GOROOT = "${pkgs.go}/share/go";
      };

      home.packages = [
        pkgs.golangci-lint
      ];
    };
}
