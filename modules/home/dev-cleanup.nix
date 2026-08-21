_: {
  # Reclaim the dev-artifact sinks that silently balloon /:
  #
  #   1. Docker — build cache, dangling images, *anonymous* volumes, and
  #      orphaned buildx builder state. These regularly grow into the
  #      tens-to-hundreds of GB (a deleted multiarch buildx builder once left
  #      a 33 GB `buildx_buildkit_*_state` volume behind). All of it is
  #      regenerable, so a periodic prune is safe — but only for artifacts
  #      with no live reference. We deliberately NEVER prune:
  #        - named volumes (project DBs, e.g. `elementor-calendar_db`,
  #          `minikube`) — they hold real data even when "dangling"
  #          (= just not attached to a running container right now).
  #        - tagged images — `image prune` (no `-a`) only drops untagged
  #          layers, never an image you might still `docker run`.
  #      so the prune is restricted to 64-hex anonymous volumes and to
  #      buildx state volumes whose builder no longer exists.
  #
  #   2. Cargo `target/` dirs under ~/git — a single Rust project's target
  #      reached 166 GB here. We remove only targets not touched in 30 days
  #      (next `cargo build` rebuilds them), and only when a sibling
  #      Cargo.toml confirms it really is a cargo build dir.
  #
  #   3. Claude Code session transcripts in ~/.claude/projects — one .jsonl
  #      per session, ~500 MB across 400+ files. Claude Code's own
  #      `cleanupPeriodDays` sweep would do this, but it cannot tell a
  #      session you deliberately named from a throwaway one. So we prune at
  #      14 days and exempt any transcript holding a `custom-title` record
  #      (written by `/rename`) — an explicit name means keep it. Only
  #      depth-2 *.jsonl files are touched, never the `memory/` and `cship/`
  #      sibling dirs that also live under a project.
  #
  # Weekly, low priority (Nice + idle IO) so it never competes with
  # interactive work. Docker steps are gated on features.docker.
  flake.modules.homeManager.devCleanup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      dockerEnabled = config.features.docker;

      # Stale cargo target dirs are cleaned regardless of docker; the docker
      # block is skipped entirely when docker is off. `docker` itself is the
      # host client (/usr/bin or /run/current-system), resolved via the unit
      # PATH below — systemd user units start with a minimal PATH and do not
      # inherit the interactive shell's, same as srv-daemon.
      cleanupScript = pkgs.writeShellScript "dev-cleanup" ''
        set -u

        find="${pkgs.findutils}/bin/find"
        grep="${pkgs.gnugrep}/bin/grep"

        # --- Cargo: stale target/ dirs under ~/git ----------------------
        # mtime +30: dir untouched for 30 days. Confirm a sibling Cargo.toml
        # so we never nuke a coincidentally-named `target` dir. -prune stops
        # find from descending into the (huge) match before we remove it.
        "$find" "$HOME/git" -mindepth 2 -maxdepth 6 -type d -name target -mtime +30 -prune -print0 2>/dev/null \
          | while IFS= read -r -d "" t; do
              if [ -f "$(dirname "$t")/Cargo.toml" ]; then
                echo "rm stale cargo target: $t"
                rm -rf "$t"
              fi
            done

        # --- Claude Code: stale, unnamed session transcripts ------------
        # mtime +14 and no custom-title record. mtime tracks appends, so a
        # resumed session keeps resetting its own clock. maxdepth 2 keeps us
        # to <project>/<uuid>.jsonl and out of memory/ and cship/.
        "$find" "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' -mtime +14 -print0 2>/dev/null \
          | while IFS= read -r -d "" f; do
              if ! "$grep" -qF '"type":"custom-title"' "$f"; then
                echo "rm stale session: $f"
                # `<uuid>/subagents/` sidecars belong to this session and
                # would orphan without it, so they go with the parent — and
                # inherit its custom-title exemption for free.
                rm -rf "$f" "''${f%.jsonl}"
              fi
            done

        ${lib.optionalString dockerEnabled ''
          docker="$(command -v docker || true)"
          if [ -n "$docker" ]; then
            # Build cache: nothing references it once a build finishes.
            "$docker" builder prune -f >/dev/null 2>&1 || true
            # Dangling (untagged) image layers only — never tagged images.
            "$docker" image prune -f >/dev/null 2>&1 || true

            # Anonymous volumes (64-hex names) with no container attached.
            # Named volumes are skipped by the regex — they may hold data.
            "$docker" volume ls -f dangling=true -q 2>/dev/null \
              | "$grep" -E '^[0-9a-f]{64}$' \
              | while IFS= read -r v; do "$docker" volume rm "$v" >/dev/null 2>&1 || true; done

            # Orphaned buildx builder state: `buildx_buildkit_<name>0_state`
            # whose <name> is no longer a registered builder.
            "$docker" volume ls -q 2>/dev/null | "$grep" -E '^buildx_buildkit_.*_state$' \
              | while IFS= read -r v; do
                  b="''${v#buildx_buildkit_}"
                  b="''${b%0_state}"
                  if ! "$docker" buildx inspect "$b" >/dev/null 2>&1; then
                    echo "rm orphaned buildx state: $v"
                    "$docker" volume rm "$v" >/dev/null 2>&1 || true
                  fi
                done
          fi
        ''}
      '';
    in
    {
      systemd.user.services.dev-cleanup = {
        Unit.Description = "Prune dev build artifacts (cargo targets, docker cache/volumes, stale Claude sessions)";
        Service = {
          Type = "oneshot";
          ExecStart = "${cleanupScript}";
          # Never compete with interactive work.
          Nice = 19;
          IOSchedulingClass = "idle";
          # Minimal-PATH user unit must be told where the host docker lives.
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
          ];
        };
      };

      systemd.user.timers.dev-cleanup = {
        Unit.Description = "Weekly dev build-artifact cleanup";
        Timer = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
