# Factory helpers that turn declarative activation metadata into ordinary
# home-manager module VALUES.
#
# Each file under modules/activation/{non-privileged,privileged}/ wraps its
# metadata ({ enableIf ?, args } shape) in a call to one of these,
# registering itself explicitly under flake.modules.homeManager.<key> —
# there is no filename convention or directory scanning: the key name in
# each file IS the registration, following the repo-wide path-derived rule
# (setup-greetd.nix → setupGreetd).
#
# History: this used to live in modules/activation/_helpers.nix with two
# dispatcher files auto-collecting sibling files by readDir; moving it to
# lib/ removed the underscore opt-outs entirely and made every activation
# a first-class dendritic module like everything else under modules/.

let
  # Fail fast when an activation module forgets to set actionScript (the
  # only required field). Without this assert the activation lands empty
  # and any error surfaces as a silent no-op at switch time.
  requireActionScript =
    name: resolved:
    if resolved ? actionScript then
      resolved
    else
      throw "activation '${name}': missing 'actionScript' (got keys: ${builtins.concatStringsSep ", " (builtins.attrNames resolved)})";
in
rec {
  inherit requireActionScript;

  # Build a PLAIN home-manager activation module. Runs unprivileged with
  # the user's permissions on every host (NixOS included).
  #
  #   mkSetupModule {
  #     name = "setupAerc";                 # also the DAG node name
  #     after = [ "browserNewtab" ];        # optional DAG ordering
  #     enableIf = { config, ... }: ...;    # optional moduleArgs gate
  #     args = { config, pkgs, homeLib, ... }: { actionScript = ...; };
  #   }
  #
  # The returned lambda closes over the FULL home-manager moduleArgs so
  # enableIf/args thunks see exactly what a hand-written module would.
  mkSetupModule =
    {
      name,
      args,
      enableIf ? true,
      after ? [ ],
    }:
    {
      config,
      lib,
      pkgs,
      homeLib,
      ...
    }@margs:
    let
      resolvedArgs = requireActionScript name (if builtins.isFunction args then args margs else args);
      isEnabled = if builtins.isFunction enableIf then enableIf margs else enableIf;
    in
    lib.mkIf isEnabled {
      home.activation.${name} = lib.hm.dag.entryAfter (
        [ "writeBoundary" ] ++ after
      ) resolvedArgs.actionScript;
    };

  # Build a SUDO-PROMPTED activation module for privileged system state
  # (pam.d, polkit rules, apparmor profiles, host package manager …).
  # Skipped on NixOS hosts, where modules/nixos/ owns those files.
  #
  # The fields may additionally carry preCheck / stateInputs / promptTitle
  # / promptBody consumed by homeLib.sudoPromptScript.
  mkSudoSetupModule =
    {
      name,
      args,
      enableIf ? true,
    }:
    {
      lib,
      config,
      pkgs,
      homeLib,
      ...
    }@margs:
    let
      resolvedArgs = requireActionScript name (if builtins.isFunction args then args margs else args);
      isEnabled = if builtins.isFunction enableIf then enableIf margs else enableIf;
      # sudoPromptScript already injects a `sudo()` shell function around
      # actionScript, so the script is free to call `sudo …` without
      # locating the binary itself. No further wrapping needed here.
      setupScript = homeLib.sudoPromptScript (
        resolvedArgs
        // {
          inherit pkgs name;
        }
      );
    in
    lib.mkIf (isEnabled && config.host.platform != "nixos") {
      home.activation.${name} = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${setupScript}
      '';
    };
}
