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
      environment.systemPackages = [ pkgs.attic-client ];

      # Without this, system packages fall back to a vanilla nixpkgs eval and
      # miss every override. Read from the flake level, not `pkgs.stubbe`:
      # `pkgs` is built FROM these values, so that is infinite recursion.
      nixpkgs = {
        config = flakeConfig.stubbe.lib.nixpkgsConfig;
        overlays = builtins.attrValues flakeConfig.flake.overlays;
      };

      nix = {
        package = inputs.determinate-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
            "parallel-eval"
          ];

          # 0 = one evaluator thread per core. Only Determinate's evaluator has
          # this; the win is ~26s -> ~18s on a no-op rebuild here.
          eval-cores = 0;

          # The HM-side copy only applies to standalone HM, so without this the
          # daemon misses nix-community and rebuilds from source.
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

        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

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

      # Persistent timers fire at the next boot after a missed run, and nix-gc
      # saturates disk IO long enough to leave the desktop blank after login.
      # Idle scheduling makes it yield to anything interactive.
      systemd.services = {
        nix-gc.serviceConfig = {
          ExecStartPre = [
            "${lib.getExe' config.nix.package "nix-env"} --profile /nix/var/nix/profiles/system --delete-generations +2"
          ];
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
      profilesDir = "${config.home.homeDirectory}/.local/state/nix/profiles";
      accessTokensFile = "${config.home.homeDirectory}/.config/nix/access-tokens.conf";
    in
    {
      home.packages = lib.mkIf config.features.development (
        with pkgs;
        [
          nix-zsh-completions
          pass
          cachix
          attic-client
          xilo
          nixd
          nixdoc
          nil
        ]
      );

      # home-manager never prunes: its generation symlinks accumulate forever
      # and pin every store path they reference.
      stubbe.setup.pruneNixGenerations.script =
        lib.concatMapStrings
          (profile: ''
            if [ -e ${lib.escapeShellArg "${profilesDir}/${profile}"} ]; then
              $DRY_RUN_CMD ${lib.getExe' config.nix.package "nix-env"} \
                --profile ${lib.escapeShellArg "${profilesDir}/${profile}"} --delete-generations +2 || true
            fi
          '')
          [
            "home-manager"
            "profile"
            "channels"
          ];

      systemd.user = lib.mkIf (!onNixOS) {
        services.nix-collect-garbage = {
          Unit.Description = "Collect unreachable nix store paths";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe' config.nix.package "nix-collect-garbage";
          };
        };

        timers.nix-collect-garbage = {
          Unit.Description = "Weekly nix store garbage collection";
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
            Unit = "nix-collect-garbage.service";
          };
          Install.WantedBy = [ "timers.target" ];
        };
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
