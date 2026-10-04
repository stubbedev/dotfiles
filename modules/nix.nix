{ config, inputs, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.nix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Without this, system packages fall back to a vanilla nixpkgs eval and
      # miss every override. Read from the flake level, not `pkgs.stubbe`:
      # `pkgs` is built FROM these values, so that is infinite recursion.
      nixpkgs = {
        config = flakeConfig.stubbe.lib.nixpkgsConfig;
        overlays = builtins.attrValues flakeConfig.flake.overlays;
      };

      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          # `<nixpkgs>` resolves to the flake's pinned tree.
          nix-path = [ "nixpkgs=${inputs.nixpkgs}" ];

          # Upstream nix evaluates single-threaded (~26s per no-op rebuild
          # here); Determinate nix was dropped for its version drift and
          # opaque errors, and its parallel evaluator went with it.

          # The HM-side copy only applies to standalone HM, so without this the
          # daemon falls back to default substituters and misses nix.stubbe.dev.
          inherit (pkgs.stubbe.cache) substituters trusted-public-keys;

          # nix asks the substituter before building, so our self-hosted cache
          # 404s until the push seconds later. The default 3600s negative TTL
          # would then hide the pushed path for an hour.
          narinfo-cache-negative-ttl = 0;

          # At the 1 MiB default the NAR decompressor blocks as soon as the
          # buffer fills and downloads run in lockstep with the writer.
          download-buffer-size = 128 * 1024 * 1024;

          auto-optimise-store = true;

          # The default `@users` lets any local user trigger store writes.
          allowed-users = [ "@wheel" ];
          trusted-users = [
            "root"
            "@wheel"
          ];
        };

        # Optional form, so an early-boot eval before the secret exists is fine.
        extraOptions = ''
          !include ${config.sops.templates."nix-access-tokens.conf".path}
        '';

        daemonCPUSchedPolicy = "idle";
        daemonIOSchedClass = "idle";

        # Old generation symlinks are GC roots, so they must be pruned BEFORE
        # collecting or there is nothing to free. `--delete-older-than` is
        # time-based and lets the count drift with switch frequency.
        gc = {
          automatic = true;
          dates = "weekly";
          options = "";
        };

        optimise = {
          automatic = true;
          dates = [ "weekly" ];
        };

        # A stale `nix-channel --update` could drift the system off flake.lock.
        channel.enable = false;
      };

      # Idle scheduling makes the weekly timers yield to anything interactive.
      systemd.services = {
        nix-gc.serviceConfig = {
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
        };
        nix-optimise.serviceConfig = {
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
        };
      };

      system.activationScripts = {
        pruneSystemGenerations.text = ''
          ${lib.getExe' config.nix.package "nix-env"} --profile /nix/var/nix/profiles/system --delete-generations +2 || true
        '';

      };

      # Rendered into /run, not the store: `nix.settings.access-tokens` would
      # put the token in the world-readable nix.conf. Owned by primaryUser
      # because `nix flake update` runs unprivileged even on NixOS.
      sops = {
        secrets.github-token = pkgs.stubbe.secret { name = "github-token"; };
        templates."nix-access-tokens.conf" = {
          content = "access-tokens = github.com=${config.sops.placeholder.github-token}";
          owner = config.host.primaryUser;
          mode = "0400";
        };
      };
    };

  flake.modules.homeManager.nix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      onNixOS = config.host.platform == "nixos";
      accessTokensFile = "${config.home.homeDirectory}/.config/nix/access-tokens.conf";
    in
    {
      home.packages = lib.mkIf config.features.development (
        with pkgs;
        [
          nix-zsh-completions
          xilo
          nixd
          nixdoc
          nil
        ]
      );

      # Weekly expiry replaces both the old activation-time +2 prune of the
      # home-manager/profile/channels profiles and the hand-rolled store GC
      # timer. Store cleanup stays standalone-only: on NixOS the system
      # nix.gc above already sweeps the whole store weekly.
      services.home-manager.autoExpire = {
        enable = true;
        timestamp = "-30 days";
        frequency = "weekly";
        store.cleanup = lib.mkIf (!onNixOS) true;
      };

      # Anonymous api.github.com allows 60 requests/hr, and `nix flake update`
      # resolves every input HEAD against it, so one run exhausts the budget and
      # silently falls back to stale cached revs.
      #
      # Pulled in by reference, not through `nix.settings.access-tokens`: that
      # would put the token in the world-readable store copy of nix.conf.
      # `!include` is the optional form, so a nix call before the first sops
      # render -- or after a reboot wipes $XDG_RUNTIME_DIR, until
      # sops-nix.service re-renders -- is fine rather than a hard error.
      #
      # On NixOS the system nix.conf carries the same line (see the nixos
      # module above) and generating a user nix.conf here would shadow it.
      sops = lib.mkIf (!onNixOS) {
        secrets.github-token = pkgs.stubbe.secret { name = "github-token"; };
        templates."nix-access-tokens.conf" = {
          content = "access-tokens = github.com=${config.sops.placeholder.github-token}";
          path = accessTokensFile;
        };
      };

      nix.extraOptions = lib.mkIf (!onNixOS) ''
        !include ${accessTokensFile}
      '';
    };
}
