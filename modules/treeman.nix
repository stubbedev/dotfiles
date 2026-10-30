{ inputs, ... }:
{
  flake.modules.homeManager.treeman =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      treemanPkgs = inputs.treeman.packages.${pkgs.stdenv.hostPlatform.system};
    in
    lib.mkIf config.features.treeman {
      home.packages = [
        treemanPkgs.treeman
        treemanPkgs.treemand
      ];

      stubbe.zshCompletions._treeman = "${lib.getExe' treemanPkgs.treeman "treeman"} completion zsh";

      xdg.configFile."treeman/config.yaml" = {
        source = pkgs.stubbe.gen.yaml "treeman-config.yaml" {
          notifications = {
            enabled = true;
            events = [
              "stable"
              "failed"
            ];
          };

          snapshots.cap_per_repo = 50;

          auto_fetch = {
            enabled = true;
            interval_minutes = 30;
          };
        };
        force = true;
      };

      systemd.user.services.treemand = {
        Unit.Description = "Treeman per-worktree DB orchestrator daemon";
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "simple";
          ExecStart = "${lib.getExe' treemanPkgs.treemand "treemand"}";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    };
}
