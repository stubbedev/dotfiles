{ config, ... }:
{
  flake.modules.nixos.nixSettings =
    { ... }:
    {
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Restrict who can talk to the nix-daemon. Default `@users` lets
      # any local user trigger evaluation / store paths; tighten to
      # wheel only since the only consumer is the primary user.
      nix.settings.allowed-users = [ "@wheel" ];
      nix.settings.trusted-users = [
        "root"
        "@wheel"
      ];

      # Backgrounded gc + builds shouldn't fight foreground apps.
      # systemd CPUSchedulingPolicy=idle = SCHED_IDLE, run only when
      # nothing else wants the CPU. IOSchedulingClass=idle = same for
      # disk I/O. Foreground latency stays clean during big rebuilds.
      nix.daemonCPUSchedPolicy = "idle";
      nix.daemonIOSchedClass = "idle";

      # Mirror the HM-bridge config so environment.systemPackages and any
      # NixOS-side `pkgs.*` reference resolve through the same overlays
      # (nixgl, cship, opencode) the HM build sees. Without this, system
      # packages fall back to a vanilla nixpkgs eval and miss the overrides.
      nixpkgs.config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "dcraw-9.28.0"
        ];
      };

      nixpkgs.overlays = builtins.attrValues config.flake.overlays;
    };
}
