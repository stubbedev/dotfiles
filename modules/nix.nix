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
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

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
    in
    {
      home.packages = lib.mkIf config.features.development (
        with pkgs;
        [
          nix-zsh-completions
          # nh ships unconditionally via modules/scripts.nix.
          pass
          cachix
          attic-client
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
              $DRY_RUN_CMD ${lib.getExe' pkgs.nix "nix-env"} \
                --profile ${lib.escapeShellArg "${profilesDir}/${profile}"} --delete-generations +2 || true
            fi
          '')
          [
            "home-manager"
            "profile"
            "channels"
          ];

      # Non-NixOS only: on NixOS the system nix-gc.service collects.
      systemd.user = lib.mkIf (!onNixOS) {
        services.nix-collect-garbage = {
          Unit.Description = "Collect unreachable nix store paths";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe' pkgs.nix "nix-collect-garbage";
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
      stubbe.setup.nixGithubToken = {
        privileged = true;
        title = "GitHub access token for Nix flake fetches";
        body = ''
          Writes `access-tokens = github.com=<token>` to
          /etc/nix/nix-access-tokens.conf (root:<your-group>, 0640) and pulls it
          into /etc/nix/nix.conf via `!include`, so `nix flake update`
          authenticates to the GitHub API (60 req/hr anonymous → 5000 req/hr).

          The token is decrypted from secrets/github-token at activation; it
          never lands in the Nix store or in the activation script.
        '';
        preCheck = ''
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
          # No nix → nothing to configure.
          if ! command -v nix >/dev/null 2>&1; then
            exit 0
          fi
          # The age identity is derived from the SSH key; without it we cannot
          # decrypt. Skip silently rather than prompt for sudo we cannot use.
          if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            exit 0
          fi
        '';
        # This text is hashed to gate the sudo re-prompt, so it must embed
        # nothing that churns between switches -- notably not `${pkgs.sops}`,
        # which moves on every nixpkgs bump.
        script =
          let
            secret = pkgs.stubbe.file "secrets/github-token";
            profileBin = config.stubbe.paths.nixBin;
          in
          ''
            # Derive the age identity straight from the SSH key (the same path
            # sops-nix uses) so this does not depend on
            # ~/.config/sops/age/keys.txt having been materialised yet — that
            # activation runs after ours.
            ageKey=$(${profileBin}/ssh-to-age -private-key -i "$HOME/.ssh/id_ed25519")
            token=$(SOPS_AGE_KEY="$ageKey" ${profileBin}/sops --decrypt \
              --input-type binary --output-type binary \
              "${secret}" | tr -d '\n')
            unset ageKey

            if [ -z "$token" ]; then
              echo "nix-github-token: decrypted token is empty, aborting." >&2
              exit 1
            fi

            # root-owned, but group = the invoking user so their unprivileged
            # `nix flake update` can still read it (0640). Write via a
            # 0077-umask tmp file then `install`, so the token is never
            # world-readable even for the instant before a chmod.
            grp=$(id -gn)
            umask 077
            tmp=$(mktemp)
            printf 'access-tokens = github.com=%s\n' "$token" > "$tmp"
            unset token
            sudo install -m 0640 -o root -g "$grp" "$tmp" /etc/nix/nix-access-tokens.conf
            rm -f "$tmp"

            # Reference it from the main config. `!include` (leading bang) is
            # the optional form: no error if the file is later removed.
            # Appended once, idempotently; the installer-managed nix.conf is
            # left otherwise untouched. The relative path resolves against
            # /etc/nix.
            if ! grep -qxF '!include nix-access-tokens.conf' /etc/nix/nix.conf 2>/dev/null; then
              printf '\n# managed-by: stubbe nix-github-token\n!include nix-access-tokens.conf\n' \
                | sudo tee -a /etc/nix/nix.conf >/dev/null
            fi
          '';
      };
    };
}
