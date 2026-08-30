# Nix itself: package set, binary caches, garbage collection, and the GitHub
# token that keeps `nix flake update` off the anonymous API rate limit.
{ config, inputs, ... }:
let
  # The NixOS module below shadows `config` with its own, so alias the
  # flake-parts one for the overlay list.
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

      # Mirror the standalone-HM nixpkgs instantiation (modules/core/flake.nix)
      # from the same shared values, so `pkgs.<x>` on the system side resolves
      # through the same overlays the HM build sees. Without this, system
      # packages fall back to a vanilla nixpkgs eval and miss every override.
      # Read from the flake level, NOT from `pkgs.stubbe`: `pkgs` is built FROM
      # these values, so reaching through it here is an infinite recursion.
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

          # Daemon-level substituters — what `nixos-rebuild` and any root-side
          # nix invocation read. The HM-side copy in modules/core/home.nix only
          # applies to the standalone-HM target (useGlobalPkgs gates it off
          # here). Without this, system rebuilds miss the nix-community cache
          # (fenix, lanzaboote, …) and rebuild from source.
          inherit (pkgs.stubbe.cache) substituters trusted-public-keys;

          # Don't let a "path absent" verdict linger. nix queries substituters
          # for a build's output path BEFORE building it; on our self-hosted
          # cache that path is a 404 until we push it seconds later, and the
          # default 3600s negative TTL then hides the freshly-pushed path for an
          # hour — so `build → push → substitute` looks broken. 0 = always
          # re-check, which is cheap on a fast link to a close cache.
          narinfo-cache-negative-ttl = 0;

          # 1 MiB (the nix default) stalls substitution: the NAR decompressor
          # blocks the moment the buffer fills, so downloads run in lockstep
          # with the writer ("warning: download buffer is full"). 128 MiB is
          # RAM we have and keeps the stream moving.
          download-buffer-size = 128 * 1024 * 1024;

          # Hardlink-dedupe identical files on every add, rather than waiting
          # for the weekly `nix.optimise` run. Cheap per build, and it keeps
          # store growth smooth between GC cycles.
          auto-optimise-store = true;

          # Restrict who can talk to the daemon. The default `@users` lets any
          # local user trigger evaluation and store writes; the only consumer
          # here is the primary user.
          allowed-users = [ "@wheel" ];
          trusted-users = [
            "root"
            "@wheel"
          ];
        };

        # `!include` (the optional form) so an early-boot evaluation before the
        # secret is rendered does not error.
        extraOptions = ''
          !include ${config.sops.templates."nix-access-tokens.conf".path}
        '';

        # Pin <nixpkgs> for system-side nix invocations (nixos-rebuild, root nix
        # repl, anything reading NIX_PATH from the daemon environment). The
        # user-side NIX_PATH for nixd/nvim is set in modules/shell.nix.
        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

        # Backgrounded GC and builds should not fight foreground apps.
        # SCHED_IDLE + idle IO class = run only when nothing else wants the
        # CPU or the disk, so foreground latency stays clean during rebuilds.
        daemonCPUSchedPolicy = "idle";
        daemonIOSchedClass = "idle";

        # Garbage-collect weekly, and keep the system profile trimmed to
        # "current + 1 previous" so a rebuild that boots poorly is still
        # instantly rollback-able without months of stale generations holding
        # hundreds of GB live.
        #
        # `nix-collect-garbage` only frees paths with no remaining GC root, and
        # old generation symlinks ARE roots — so generations must be pruned
        # BEFORE collecting or there is nothing to free. `--delete-older-than`
        # is time-based and lets the count drift; `--delete-generations +2`
        # enforces a count regardless of switch frequency.
        gc = {
          automatic = true;
          dates = "weekly";
          options = "";
        };

        optimise = {
          automatic = true;
          dates = [ "weekly" ];
        };

        # Flake-only system: the nix-channel CLI and its update timer are dead
        # weight, and a stale `nix-channel --update` could drift the system away
        # from the flake.lock pin.
        channel.enable = false;
      };

      # The gc/optimise timers are weekly + Persistent, so a run missed while
      # the machine was off fires at the NEXT boot — nix-gc alone is ~3.5min of
      # saturated disk IO, which starves the compositor and leaves the desktop
      # blank for ~90s after login. Idle IO/CPU scheduling makes both yield to
      # anything interactive: login stays fast, maintenance still completes.
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
        # Prune on every switch too, so generations do not accumulate between
        # weekly GC runs — same shape as the HM activation below.
        pruneSystemGenerations.text = ''
          ${lib.getExe' config.nix.package "nix-env"} --profile /nix/var/nix/profiles/system --delete-generations +2 || true
        '';

      };

      # GitHub API token for flake input fetches. sops-nix decrypts it into /run
      # and the template renders the nix.conf line there, so the token never
      # lands in the world-readable /nix/store copy of nix.conf — which
      # `nix.settings.access-tokens` would do. owner = primaryUser because
      # `nix flake update` runs unprivileged even on NixOS, so the user's own
      # client must be able to read it; root/daemon reads it regardless.
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
          # nh ships unconditionally via modules/scripts.nix (the `hm` wrapper
          # depends on it), so it is deliberately absent here.
          pass
          cachix
          attic-client
          nixd
          nixdoc
          nil
        ]
      );

      # home-manager's switch does NOT prune old generations: the
      # ~/.local/state/nix/profiles/{home-manager,profile,channels}-N-link
      # symlinks accumulate forever and pin every store path they reference,
      # which is by far the biggest source of store bloat on a host that
      # rebuilds many times a day. Trim to "current + 1 previous" on every
      # switch, so a switch cleans up after itself.
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

      # Actually free the store paths whose last GC root the prune above
      # removed. Non-NixOS only: on NixOS the system nix-gc.service collects.
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

      # Non-NixOS: HM owns /etc/nix here, so the same token has to be written
      # by an activation. api.github.com caps anonymous requests at 60/hr per
      # IP, and `nix flake update` resolves every input's HEAD against that
      # API — a flake with ~20 github inputs exhausts the budget in one run and
      # falls back to stale cached revs ("HTTP error 403 … rate limit exceeded
      # … using cached version"). A token lifts the cap to 5000/hr.
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
        # The script's text is hashed to gate the sudo re-prompt, so it must not
        # embed anything that churns between switches. Both references below are
        # stable: `pkgs.stubbe.file` is content-addressed on the ciphertext (so
        # it changes exactly when the token is rotated — precisely when we DO
        # want a re-prompt), and profileDirectory/bin is a fixed string, unlike
        # `${pkgs.sops}` which moves on every nixpkgs bump.
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
