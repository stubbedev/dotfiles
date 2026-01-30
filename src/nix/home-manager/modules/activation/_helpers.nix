{
  mkSetupModule = { name, after, script, provideSudo ? false }:
    {
      flake.modules.homeManager.activation.${name} = { lib, ... }@args:
        let
          scriptText = if builtins.isFunction script then script args else script;
          sudoPrelude = if provideSudo then ''
            # Find sudo in common locations
            SUDO=""
            for path in /usr/bin/sudo /bin/sudo /run/wrappers/bin/sudo; do
              if [ -x "$path" ]; then
                SUDO="$path"
                break
              fi
            done

            if [ -z "$SUDO" ]; then
              echo "Error: sudo not found. Please install sudo or run manually."
              exit 1
            fi

            sudo() { "$SUDO" "$@"; }
          '' else "";
        in
        {
          home.activation.${name} =
            lib.hm.dag.entryAfter after (sudoPrelude + scriptText);
        };
    };

  mkSudoSetupModule = { name, after, sudoArgs, scriptName ? null }:
    {
      flake.modules.homeManager.activation.${name} = { lib, pkgs, homeLib, ... }@args:
        let
          resolvedArgs =
            if builtins.isFunction sudoArgs then sudoArgs args else sudoArgs;
          resolvedScriptName =
            if scriptName != null then scriptName else (resolvedArgs.name or name);
          withSudo = text:
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
          setupScript = homeLib.sudoPromptScript (resolvedArgsNoName // {
            inherit pkgs;
            name = resolvedScriptName;
          });
        in
        {
          home.activation.${name} =
            lib.hm.dag.entryAfter after ''
              ${setupScript}
            '';
        };
    };
}
