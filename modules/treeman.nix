{ inputs, ... }:
{
  flake.modules.nixos.treeman =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      treemanPkg = inputs.treeman.packages.${system}.treeman;
      treemandPkg = inputs.treeman.packages.${system}.treemand;
    in
    {
      environment.systemPackages = [
        treemanPkg
        treemandPkg
      ];
    };

  flake.modules.homeManager.treeman =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      treemanPkg = inputs.treeman.packages.${system}.treeman;
      treemandPkg = inputs.treeman.packages.${system}.treemand;
    in
    lib.mkIf config.features.treeman {
      home.packages = [
        treemanPkg
        treemandPkg
        (pkgs.stubbe.bashApp {
          name = "treeman-status";
          text = ''
            command -v treeman >/dev/null 2>&1 && treeman status --format waybar 2>/dev/null
          '';
        })
      ];

      xdg.configFile."treeman/config.yaml" = {
        source = (pkgs.formats.yaml { }).generate "treeman-config.yaml" {
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

          status.formats.icon = "{icon_stable} {stable}  {icon_up} {up}  {icon_down} {down}  {icon_failed} {failed}";
        };
        force = true;
      };

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

      # Force a daemon restart on every `hm switch`. home-manager's
      # sd-switch only restarts a unit when the unit file content
      # changed — when the treeman flake input bumps the file body
      # changes (ExecStart store path moves) and the restart fires on
      # its own. But for in-place rebuilds (e.g. a `nix flake update`
      # that didn't move the lock, or a manual `home-manager build`
      # against a dirty worktree) the unit looks identical and the
      # daemon stays on the old binary. Always-restart kicks the
      # daemon so the running process matches the activated
      # generation. `try-restart` is a no-op when the unit isn't
      # active, so a host with `features.treeman = false` (or one
      # that hasn't enabled the unit yet) doesn't error.
      stubbe.setup.restartTreemand = {
        after = [ "reloadSystemd" ];
        script = ''
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user try-restart treemand.service 2>/dev/null || true
          fi
        '';
      };
    };
}
