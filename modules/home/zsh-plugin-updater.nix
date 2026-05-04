_: {
  flake.modules.homeManager.zshPluginUpdater =
    {
      constants,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      pluginsDir = "${constants.paths.zsh}/plugins.d";

      # Reads the same plugin list the shell uses so there is a single source of truth.
      # The update script mirrors what manager does: fetch + pull when behind remote.
      updateScript = pkgs.writeShellScript "zsh-plugin-update" ''
        set -euo pipefail

        PLUGINS_DIR="${pluginsDir}"
        PLUGINS_FILE="${constants.paths.zsh}/plugins"

        # Extract GitHub slugs/URLs from the plugins file (lines inside the array)
        mapfile -t URLS < <(
          ${pkgs.gawk}/bin/awk '
            /local -a plugins=\(/{found=1; next}
            found && /^\)/{exit}
            found && /\"/{
              gsub(/[" ]/, ""); print
            }
          ' "$PLUGINS_FILE"
        )

        mkdir -p "$PLUGINS_DIR"

        for url in "''${URLS[@]}"; do
          [[ "$url" =~ ^https?:// ]] || url="https://github.com/$url"
          repo="$(basename "$url" .git)"
          target="$PLUGINS_DIR/$repo"

          if [[ ! -d "$target" ]]; then
            echo "ADDING: $repo"
            ${pkgs.git}/bin/git clone --depth=1 "$url.git" "$target"
            ${pkgs.zsh}/bin/zsh -c 'for f in '"$target"'/*.plugin.zsh(N); do zcompile "$f"; done' 2>/dev/null || true
          else
            ${pkgs.git}/bin/git -C "$target" fetch --quiet
            local_ref=$(${pkgs.git}/bin/git -C "$target" rev-parse @)
            remote_ref=$(${pkgs.git}/bin/git -C "$target" rev-parse '@{u}' 2>/dev/null || echo "")
            if [[ -n "$remote_ref" && "$local_ref" != "$remote_ref" ]]; then
              echo "UPDATING: $repo"
              ${pkgs.git}/bin/git -C "$target" pull --force --quiet
              ${pkgs.zsh}/bin/zsh -c 'for f in '"$target"'/*.plugin.zsh(N); do zcompile "$f"; done' 2>/dev/null || true
            fi
          fi
        done
      '';
    in
    {
      systemd.user.services.zsh-plugin-update = {
        Unit = {
          Description = "Update zsh plugins from GitHub";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${updateScript}";
          # Low priority so it doesn't compete with interactive work
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.zsh-plugin-update = {
        Unit = {
          Description = "Daily zsh plugin update timer";
        };
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "10min";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
}
