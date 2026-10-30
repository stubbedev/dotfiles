_: {
  flake.modules.homeManager.setup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sudoScript =
        name: setup:
        let
          actionHash = builtins.hashString "sha256" setup.script;
          statePathsArg = lib.escapeShellArgs setup.stateInputs;
        in
        pkgs.stubbe.shellScript "setup-${name}" ''
          set -e

          # Activations run with a stripped PATH; restore the standard
          # locations first, so sudo and every probe below (preCheck,
          # hostPackage, systemctl, ...) find their binaries. Many live
          # under /sbin.
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          if (exec >/dev/tty) 2>/dev/null; then
            exec >/dev/tty 2>&1
          fi

          if ! command -v sudo >/dev/null; then
            echo "setup-${name}: sudo not found; this privileged step cannot run" >&2
            exit 1
          fi

          stateHash=$(
            # shellcheck disable=SC2043 # nix-generated list: one path or many
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

          ${setup.script}
          mkdir -p "$HOME/.local/state/nix/home-manager"
          echo -n "$combinedHash" > "$lockFile"
          echo ""
        '';

      # A privileged step writes /etc through sudo, which only a distro
      # (platform "linux") puts in our hands: NixOS owns those files in its own
      # module, and Android's /etc is generated from the store by nix-on-droid.
      wanted = lib.filterAttrs (
        _: s: s.enable && !(s.privileged && config.host.platform != "linux")
      ) config.stubbe.setup;
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
                    on the "linux" platform. PATH is restored to the standard
                    system locations first, so `sudo` resolves directly.
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
                    to skip this step entirely. See `pkgs.stubbe.setup.requireCommand`
                    and `pkgs.stubbe.setup.requirePath`.
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

      config.assertions = lib.mapAttrsToList (name: s: {
        assertion = s.privileged || (s.preCheck == "" && s.body == "" && s.stateInputs == [ ]);
        message = "stubbe.setup.${name}: preCheck, body and stateInputs only apply to privileged steps.";
      }) config.stubbe.setup;

      config.home.activation = lib.mapAttrs (
        name: setup:
        lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ setup.after) (
          if setup.privileged then "${sudoScript name setup}" else setup.script
        )
      ) wanted;
    };
}
