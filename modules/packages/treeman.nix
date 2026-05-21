{ inputs, ... }:
{
  # Treeman per-worktree DB orchestrator + treemand user daemon.
  #
  # Two scopes:
  #   - homeManager: installs treeman + treemand into home.packages and
  #     wires the daemon as a systemd user service. This bypasses
  #     `treeman daemon install` (which writes a runtime-mutable unit
  #     under ~/.config/systemd/user/) — keeping the unit declarative
  #     means the whole stack survives a clean home-manager rebuild.
  #   - nixos: also puts the CLI + daemon binaries in
  #     environment.systemPackages so non-HM users on the box can run
  #     `treeman` from a login shell. The daemon itself stays user-scope
  #     (treeman state is per-user), so no system unit is declared here.
  #     The HM module references `treeman` as a destructured arg
  #     (injected via modules/home/context.nix); the NixOS scope has no
  #     such bridge, so we reach into `inputs.treeman` directly.
  #
  # The HM unit body mirrors contrib/treemand.service from upstream
  # (Description, After, Restart, RestartSec); only ExecStart is
  # rewritten to the Nix store path.
  flake.modules.nixos.packagesTreeman =
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
