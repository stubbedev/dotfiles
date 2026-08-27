# `stubbe.setup.<name>` — the one way this repo runs imperative work at
# activation time.
#
# Every aspect that needs a shell step (bootstrapping a maildir, editing
# /etc/pam.d, installing a host-OS package) declares it inline in its own
# aspect file. There is no factory to import, no metadata attrset to `//`
# together, and no name repeated as a string: the attribute name IS the DAG
# node name, and the option types catch a missing `script` at eval time —
# which is what the old `requireActionScript` throw was hand-rolling.
#
#   stubbe.setup.aerc.script = "…";                 # unprivileged, every host
#   stubbe.setup.zram = {                           # sudo, non-NixOS only
#     privileged = true;
#     body = "…";
#     script = "…";
#   };
#
# `privileged = true` wraps the script in the shared sudo-prompt scaffolding
# and gates it off on NixOS, where the matching `flake.modules.nixos.<aspect>`
# half owns the same system state declaratively.
_: {
  flake.modules.homeManager.setup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Sudo-prompted wrapper for a privileged setup. Produces the consistent
      # "Installing <x>" banner, and locks on a hash of the script text so a
      # switch that changes nothing costs nothing.
      sudoScript =
        name: setup:
        let
          actionHash = builtins.hashString "sha256" setup.script;
          statePathsArg = lib.escapeShellArgs setup.stateInputs;
        in
        pkgs.writeShellScript "setup-${name}" ''
          set -e

          # nh pipes (and hides) activation output, so a switch sitting in a
          # slow action (update-initramfs, mkcert -install, …) looks hung.
          # Write progress straight to the terminal when there is one.
          # `[ -w /dev/tty ]` is not enough: without a controlling terminal the
          # node exists and tests writable, but opening it fails ("No such
          # device or address") and `set -e` would abort the whole activation —
          # so probe with a real open in a subshell.
          if (exec >/dev/tty) 2>/dev/null; then
            exec >/dev/tty 2>&1
          fi

          SUDO=""
          for path in /bin/sudo /usr/bin/sudo /usr/local/bin/sudo; do
            if [ -x "$path" ]; then
              SUDO="$path"
              break
            fi
          done

          # No sudo on this host — nothing privileged is possible, so skip.
          # exit, not return: this is a top-level script, not a sourced file —
          # `return` here is a bash error that would abort the activation.
          if [ -z "$SUDO" ]; then
            exit 0
          fi

          sudo() { "$SUDO" "$@"; }

          # Fingerprint world-readable paths the script depends on, so the lock
          # invalidates when they appear or disappear (e.g. a display manager
          # getting installed after the script first ran).
          stateHash=$(
            for p in ${statePathsArg}; do
              if [ -e "$p" ]; then printf '%s:1\n' "$p"; else printf '%s:0\n' "$p"; fi
            done | sha256sum | cut -d' ' -f1
          )
          combinedHash="${actionHash}:$stateHash"

          lockFile="$HOME/.local/state/nix/home-manager/${name}.lock.sum"
          if [ -f "$lockFile" ] && [ "$(cat "$lockFile")" = "$combinedHash" ]; then
            exit 0
          fi

          ${setup.preCheck}

          echo ""
          echo "--------------------------------------------------------------------"
          printf '%s\n' ${lib.escapeShellArg setup.title}
          echo "--------------------------------------------------------------------"
          echo ""
          printf '%s\n' ${lib.escapeShellArg setup.body}

          # No confirmation prompt: activation runs behind nh, which pipes our
          # stdout/stderr, so a `read -p` blocks invisibly and the switch looks
          # hung. sudo itself still authenticates on /dev/tty when the
          # timestamp has expired, so the privilege gate stays interactive
          # where it must be.
          ${setup.script}
          mkdir -p "$HOME/.local/state/nix/home-manager"
          echo -n "$combinedHash" > "$lockFile"
          echo ""
        '';

      # A privileged setup is skipped on NixOS: modules/<aspect>.nix's nixos
      # half owns that system state there.
      onNixOS = config.host.platform == "nixos";
      wanted = lib.filterAttrs (_: s: s.enable && !(s.privileged && onNixOS)) config.stubbe.setup;
    in
    {
      options.stubbe.setup = lib.mkOption {
        description = "Activation-time shell steps, keyed by DAG node name.";
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether to run this step. Gate it on a `features.*` flag.";
                };

                script = lib.mkOption {
                  type = lib.types.lines;
                  description = ''
                    The shell to run. Idempotent, please — it runs on every
                    switch (privileged steps additionally short-circuit on a
                    hash of this text). Activations run with a stripped PATH.
                  '';
                };

                after = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra home-manager activation DAG nodes to order after.";
                };

                privileged = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    Run behind sudo with the shared prompt scaffolding, and only
                    on non-NixOS hosts. A `sudo` shell function is in scope, so
                    the script never has to locate the binary itself.
                  '';
                };

                title = lib.mkOption {
                  type = lib.types.str;
                  default = "Installing ${name}";
                  defaultText = "Installing <name>";
                  description = "Banner shown before a privileged step runs.";
                };

                body = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  description = "What the privileged step is about to do, and why, shown under the banner.";
                };

                preCheck = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  description = ''
                    Guard that runs before the banner and the sudo prompt; `exit 0`
                    to skip this step entirely. See `pkgs.stubbe.requireCommand`
                    and `pkgs.stubbe.requirePath`.
                  '';
                };

                stateInputs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    Paths whose existence is part of this step's input. The lock
                    invalidates when any of them appears or disappears, so a
                    later change in host state forces a re-run.
                  '';
                };
              };
            }
          )
        );
      };

      config.home.activation = lib.mapAttrs (
        name: setup:
        lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ setup.after) (
          if setup.privileged then "${sudoScript name setup}" else setup.script
        )
      ) wanted;
    };
}
