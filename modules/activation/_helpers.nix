let
  # Fail fast when an activation module forgets to set actionScript (the
  # only required field). Without this assert the activation lands empty
  # and any error surfaces as a silent no-op at switch time.
  requireActionScript = name: resolved:
    if resolved ? actionScript then
      resolved
    else
      throw "activation '${name}': missing 'actionScript' (got keys: ${
        builtins.concatStringsSep ", " (builtins.attrNames resolved)
      })";
in
{
  mkSetupModule =
    {
      name,
      args,
      enableIf ? true,
      after ? [ ],
    }:
    {
      flake.modules.homeManager.${name} =
        {
          config,
          lib,
          pkgs,
          homeLib,
          ...
        }@moduleArgs:
        let
          resolvedArgs = requireActionScript name
            (if builtins.isFunction args then args moduleArgs else args);
          isEnabled = if builtins.isFunction enableIf then enableIf moduleArgs else enableIf;
        in
        lib.mkIf isEnabled {
          home.activation.${name} = lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ after) resolvedArgs.actionScript;
        };
    };

  mkSudoSetupModule =
    {
      name,
      args,
      enableIf ? true,
    }:
    {
      flake.modules.homeManager.${name} =
        {
          config,
          lib,
          pkgs,
          homeLib,
          ...
        }@moduleArgs:
        let
          resolvedArgs = requireActionScript name
            (if builtins.isFunction args then args moduleArgs else args);
          isEnabled = if builtins.isFunction enableIf then enableIf moduleArgs else enableIf;
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
    };
}
