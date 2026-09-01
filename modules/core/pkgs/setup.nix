# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Shell fragments for config.stubbe.setup.<name>.script. These emit text; the
# other branches build derivations.
_: {
  stubbe.pkgsLib.setup =
    {
      final,
      lib,
      stubbe,
      ...
    }:
    {
      file =
        {
          source,
          target,
          mode ? "0644",
          owner ? "root",
          group ? "root",
        }:
        ''
          sudo install -D -m ${mode} -o ${owner} -g ${group} ${source} ${lib.escapeShellArg target}
        '';

      link =
        { source, target }:
        ''
          sudo install -d -m 0755 ${lib.escapeShellArg (dirOf target)}
          sudo ln -sfT ${source} ${lib.escapeShellArg target}
        '';

      text =
        {
          name,
          text,
          ...
        }@args:
        stubbe.setup.file (
          removeAttrs args [
            "name"
            "text"
          ]
          // {
            source = final.writeText name text;
          }
        );

      # `detect` names a command; `have` takes an arbitrary test for cases where
      # what gets installed is a file rather than something on PATH.
      hostPackage =
        {
          detect ? null,
          have ? "command -v ${detect} >/dev/null 2>&1",
          apt,
          dnf,
          pacman,
        }:
        ''
          if ! { ${have}; }; then
            if command -v apt-get >/dev/null 2>&1; then
              sudo apt-get update
              sudo apt-get install -y --no-install-recommends ${lib.escapeShellArgs apt}
            elif command -v dnf >/dev/null 2>&1; then
              sudo dnf install -y --setopt=install_weak_deps=False ${lib.escapeShellArgs dnf}
            elif command -v pacman >/dev/null 2>&1; then
              sudo pacman -S --needed --noconfirm ${lib.escapeShellArgs pacman}
            else
              echo "No supported package manager (apt-get/dnf/pacman) found." >&2
              exit 1
            fi
          fi
        '';

      # Both reloads are guarded: setup scripts run under `set -e`, so an
      # unguarded systemctl aborts the whole entry on a host without systemd.
      reloadUnits = ''
        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl daemon-reload
        fi
      '';

      reloadUdev = ''
        if command -v udevadm >/dev/null 2>&1; then
          sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        fi
      '';

      # Rules want root:polkitd where that group exists, root:root otherwise.
      polkitRule =
        { source, target }:
        ''
          ${stubbe.setup.file { inherit source target; }}
          if getent group polkitd >/dev/null 2>&1; then
            sudo chown root:polkitd ${lib.escapeShellArg target}
          fi
          if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl restart polkit.service >/dev/null 2>&1 || true
          fi
        '';

      # Each exits 0 so the rest of the setup, including its sudo prompt, is
      # skipped. PATH is restored first: activations run stripped and many
      # probes live under /sbin.
      requireCommand = cmd: ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
        if ! command -v ${cmd} >/dev/null 2>&1; then
          exit 0
        fi
      '';

      requirePath = path: ''
        if [ ! -e ${lib.escapeShellArg path} ]; then
          exit 0
        fi
      '';

      # Ubuntu 24.04+ limits unprivileged userns to binaries with a matching
      # AppArmor profile, and nix-store paths match none of the stock ones, so
      # Chromium and bubblewrap abort with "No usable sandbox!".
      apparmor =
        {
          appName,
          profileName,
          programGlob,
        }:
        {
          privileged = true;
          preCheck = stubbe.setup.requireCommand "apparmor_status";
          title = "Installing AppArmor profile for Nix-installed ${appName}";
          body = ''
            Ubuntu 24.04 restricts unprivileged user namespaces (required by
            Chromium-based sandboxes) to binaries with a matching AppArmor
            profile. Nix-store paths aren't covered by Ubuntu's stock profiles,
            so ${appName} aborts on launch with "No usable sandbox!".

            This installs an AppArmor profile that whitelists the Nix-store
            ${appName} binary (and its sandbox helper) for unprivileged userns.
          '';
          script = ''
            ${stubbe.setup.text {
              name = profileName;
              target = "/etc/apparmor.d/${profileName}";
              text = ''
                # managed-by: stubbe ${profileName}
                abi <abi/4.0>,
                include <tunables/global>
                profile ${profileName} ${programGlob} flags=(unconfined) {
                  userns,
                  @{exec_path} mr,
                  include if exists <local/${profileName}>
                }
              '';
            }}
            sudo apparmor_parser -r ${lib.escapeShellArg "/etc/apparmor.d/${profileName}"}
          '';
        };

      # jq against the LIVE file, so anything the owning app wrote between
      # evaluation and activation survives.
      # jsonMerge is additive; jsonSet REPLACES one key, so entries dropped
      # from `value` actually disappear.
      jsonMerge =
        {
          name,
          target,
          patch,
          mode ? "0600",
        }:
        let
          patchFile = (final.formats.json { }).generate "${name}.json" patch;
        in
        ''
          mkdir -p "$(dirname ${lib.escapeShellArg target})"
          if [ -f ${lib.escapeShellArg target} ]; then
            ${lib.getExe final.jq} -s '(.[0] // {}) * .[1]' ${lib.escapeShellArg target} ${patchFile} \
              > ${lib.escapeShellArg "${target}.hm-tmp"}
            if cmp -s ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}; then
              rm -f ${lib.escapeShellArg "${target}.hm-tmp"}
            else
              mv ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}
            fi
          else
            install -D -m ${mode} ${patchFile} ${lib.escapeShellArg target}
          fi
        '';

      jsonSet =
        {
          name,
          target,
          key,
          value,
          mode ? "0600",
        }:
        let
          valueFile = (final.formats.json { }).generate "${name}.json" value;
        in
        ''
          mkdir -p "$(dirname ${lib.escapeShellArg target})"
          if [ -f ${lib.escapeShellArg target} ]; then
            ${lib.getExe final.jq} --slurpfile v ${valueFile} '.[${builtins.toJSON key}] = $v[0]' \
              ${lib.escapeShellArg target} > ${lib.escapeShellArg "${target}.hm-tmp"}
            if cmp -s ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}; then
              rm -f ${lib.escapeShellArg "${target}.hm-tmp"}
            else
              mv ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}
            fi
          else
            ${lib.getExe final.jq} -n --slurpfile v ${valueFile} '{ ${builtins.toJSON key}: $v[0] }' \
              > ${lib.escapeShellArg target}
            chmod ${mode} ${lib.escapeShellArg target}
          fi
        '';

      # ── Config generators ──────────────────────────────────────────────
      # gen.<fmt> name value -> store path. conf.<fmt> maps
      # { "<path>" = <value>; } straight into xdg.configFile shape, so a
      # module states each config file once instead of repeating its name and
      # reaching for lib.mkMerge.

    };
}
