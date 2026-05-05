{
  mkSetupModule =
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
          resolvedArgs = if builtins.isFunction args then args moduleArgs else args;
          isEnabled = if builtins.isFunction enableIf then enableIf moduleArgs else enableIf;
        in
        lib.mkIf isEnabled {
          home.activation.${name} = lib.hm.dag.entryAfter [ "writeBoundary" ] resolvedArgs.actionScript;
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
          resolvedArgs = if builtins.isFunction args then args moduleArgs else args;
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
