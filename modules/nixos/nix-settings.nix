{ config, inputs, self, ... }:
let
  cache = import (self + "/lib/nix-cache.nix");
  # The NixOS module below needs its own `config` (for sops + host options),
  # which shadows this flake-level one — alias it so `config.flake.overlays`
  # still resolves.
  flakeConfig = config;
in
{
  flake.modules.nixos.nixSettings =
    { config, ... }:
    {
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # GitHub API token for flake input fetches. Anonymous api.github.com
      # is capped at 60 req/hr per IP; `nix flake update` resolves every
      # input's HEAD against it and exhausts that in one run, falling back
      # to stale cached revs. An authenticated token lifts the cap to
      # 5000 req/hr. (Non-NixOS hosts get the same via the privileged
      # activation in modules/activation/_privileged/setup-nix-github-token.nix.)
      #
      # sops-nix decrypts the token into /run and the template renders the
      # nix.conf line there — so the token never lands in the world-readable
      # /nix/store copy of nix.conf (which `nix.settings.access-tokens` would
      # do). owner = primaryUser because `nix flake update` runs unprivileged
      # even on NixOS, so the user's own client must be able to read it;
      # root/daemon reads it regardless.
      sops.secrets."github-token" = {
        sopsFile = self + "/secrets/github-token";
        format = "binary";
      };
      sops.templates."nix-access-tokens.conf" = {
        content = "access-tokens = github.com=${config.sops.placeholder."github-token"}";
        owner = config.host.primaryUser;
        mode = "0400";
      };
      # `!include` (optional form) so an early-boot evaluation before the
      # secret is rendered doesn't error.
      nix.extraOptions = ''
        !include ${config.sops.templates."nix-access-tokens.conf".path}
      '';

      # Daemon-level substituters. These are what `nixos-rebuild` and any
      # root-side nix invocation read; the HM-side copy in
      # modules/home/nix.nix only applies to the standalone-HM target on
      # non-NixOS hosts (useGlobalPkgs gates it off here). Without this,
      # system rebuilds miss the nix-community cache (fenix, lanzaboote,
      # hy3, etc.) and rebuild from source.
      nix.settings.substituters = cache.substituters;
      nix.settings.trusted-public-keys = cache.trusted-public-keys;

      # Hardlink-dedupe identical files in the store on every add, instead
      # of waiting for the weekly `nix.optimise` run. Cheap per-build cost,
      # smoother store growth between GC cycles.
      nix.settings.auto-optimise-store = true;

      # Pin <nixpkgs> for system-side nix invocations (nixos-rebuild, root
      # nix repl, anything reading NIX_PATH from the daemon environment).
      # User-side NIX_PATH for nixd/nvim is set in
      # modules/home/session-variables.nix.
      nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

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
      # (nixgl, cship) the HM build sees. Without this, system
      # packages fall back to a vanilla nixpkgs eval and miss the overrides.
      nixpkgs.config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "dcraw-9.28.0"
        ];
      };

      nixpkgs.overlays = builtins.attrValues flakeConfig.flake.overlays;

      # Leftover from any pre-flake nix-channel use of this host. Channels
      # are disabled (nix.channel.enable defaults false on flake-only
      # systems) but Nix still warns at every activation while these
      # directories exist (NixOS/nix#9574). Remove on each switch — the
      # `-rf` is safe because the daemon doesn't read them when channels
      # are disabled, and recreated copies would just re-trigger the warning.
      system.activationScripts.removeLegacyNixChannels = ''
        rm -rf /root/.nix-defexpr/channels /nix/var/nix/profiles/per-user/root/channels
      '';
    };
}
