{ ... }:
{
  enableIf =
    { config, ... }:
    (config.features.media or false) && (config.features.desktop or false);
  args =
    { pkgs, lib, homeLib, ... }:
    let
      kmsServer = "${pkgs.gpu-screen-recorder}/bin/gsr-kms-server";
      getcap = "${pkgs.libcap.out}/bin/getcap";
      setcap = "${pkgs.libcap.out}/bin/setcap";
    in
    homeLib.mkInstallPrompt {
      subject = "cap_sys_admin on gsr-kms-server";
      body = ''
        gpu-screen-recorder's KMS capture helper needs CAP_SYS_ADMIN to
        record monitors without a polkit prompt on every launch. On
        NixOS the system module installs a setcap wrapper for this; on
        this non-NixOS host we set the capability directly on the
        store-path binary (xattr survives nix-store optimisation; the
        actionScript hash invalidates when the store path changes after
        a gpu-screen-recorder bump).

        Target: ${kmsServer}
      '';
      # Lockfile flips on every gpu-screen-recorder upgrade because the
      # store path is embedded. stateInputs adds a second axis: lock also
      # invalidates if the binary itself disappears between switches.
      stateInputs = [ kmsServer ];
      # Short-circuit when the cap is already in place — no sudo prompt,
      # no `setcap` invocation. Writes the lockfile ourselves so the
      # next switch hits the fast path even after a manual lockfile
      # delete or first-time setup.
      preCheck = ''
        if [ -e ${lib.escapeShellArg kmsServer} ] \
          && ${getcap} ${lib.escapeShellArg kmsServer} 2>/dev/null \
            | grep -q 'cap_sys_admin'; then
          mkdir -p "$HOME/.local/state/nix/home-manager"
          printf '%s' "$combinedHash" > "$lockFile"
          exit 0
        fi
      '';
      actionScript = ''
        target=${lib.escapeShellArg kmsServer}
        if [ ! -e "$target" ]; then
          echo "gsr-kms-server not found at $target — skipping setcap"
          exit 0
        fi
        sudo ${setcap} cap_sys_admin+ep "$target"
        echo "Applied cap_sys_admin+ep to $target"
      '';
    };
}
