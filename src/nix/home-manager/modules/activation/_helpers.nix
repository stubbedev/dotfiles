{
  mkSetupModule =
    {
      name,
      args,
      enableIf ? true,
    }:
    {
      flake.modules.homeManager.${name} =
        { lib, ... }@moduleArgs:
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
          lib,
          pkgs,
          homeLib,
          ...
        }@moduleArgs:
        let
          resolvedArgs = if builtins.isFunction args then args moduleArgs else args;
          isEnabled = if builtins.isFunction enableIf then enableIf moduleArgs else enableIf;
          withSudo =
            text:
            if text == "" then
              text
            else
              ''
                sudo() { "$SUDO" "$@"; }
                ${text}
              '';
          setupScript = homeLib.sudoPromptScript (
            resolvedArgs
            // {
              inherit pkgs name;
              actionScript = withSudo (resolvedArgs.actionScript or "");
            }
          );
        in
        lib.mkIf isEnabled {
          home.activation.${name} = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ${setupScript}
          '';
        };
    };
}
