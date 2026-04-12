{
  mkSetupModule =
    {
      moduleName,
      activationName ? moduleName,
      args,
      enableIf ? true,
    }:
    {
      flake.modules.homeManager.${moduleName} =
        { lib, ... }@moduleArgs:
        let
          resolvedArgs = if builtins.isFunction args then args moduleArgs else args;
          isEnabled = if builtins.isFunction enableIf then enableIf moduleArgs else enableIf;
        in
        lib.mkIf isEnabled {
          home.activation.${activationName} = lib.hm.dag.entryAfter [ "writeBoundary" ] resolvedArgs.actionScript;
        };
    };

  mkSudoSetupModule =
    {
      moduleName,
      activationName ? moduleName,
      args,
      enableIf ? true,
    }:
    {
      flake.modules.homeManager.${moduleName} =
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
          resolvedArgsWithSudo = resolvedArgs // {
            preCheck = withSudo (resolvedArgs.preCheck or "");
            actionScript = withSudo (resolvedArgs.actionScript or "");
          };
          resolvedArgsNoName = builtins.removeAttrs resolvedArgsWithSudo [ "name" ];
          setupScript = homeLib.sudoPromptScript (
            resolvedArgsNoName
            // {
              inherit pkgs;
              name = activationName;
            }
          );
        in
        lib.mkIf isEnabled {
          home.activation.${activationName} = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ${setupScript}
          '';
        };
    };
}
