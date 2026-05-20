_: {
  # Treeman per-worktree DB orchestrator + treemand user daemon.
  #
  # Installs the `treeman` CLI and the `treemand` daemon binary from the
  # upstream flake (github:stubbedev/treeman) and wires the daemon as a
  # home-manager systemd user service. This bypasses `treeman daemon
  # install` (which writes a runtime-mutable unit under
  # ~/.config/systemd/user/) — keeping the unit declarative means the
  # whole stack survives a clean home-manager rebuild on a fresh machine.
  #
  # The unit body mirrors contrib/treemand.service from the upstream
  # repository (Description, After, Restart, RestartSec); only ExecStart
  # is rewritten to the Nix store path.
  flake.modules.homeManager.packagesTreeman =
    {
      pkgs,
      lib,
      config,
      treeman,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      treemanPkg = treeman.packages.${system}.treeman;
      treemandPkg = treeman.packages.${system}.treemand;
    in
    lib.mkIf config.features.treeman {
      home.packages = [
        treemanPkg
        treemandPkg
      ];

      systemd.user.services.treemand = {
        Unit = {
          Description = "Treeman per-worktree DB orchestrator daemon";
          After = [ "default.target" ];
        };
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "simple";
          ExecStart = "${treemandPkg}/bin/treemand";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    };
}
