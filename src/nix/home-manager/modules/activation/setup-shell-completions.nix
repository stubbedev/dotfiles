_:
let
  order = import ./_order.nix;
in
{
  flake.modules.homeManager.activationSetupShellCompletions =
    {
      config,
      pkgs,
      lib,
      constants ? null,
      ...
    }:
    let
      homeDir = config.home.homeDirectory;
      stubbeDir = if constants != null then constants.paths.dotfiles else "${homeDir}/.stubbe";
    in
    {
      home.activation.customShellCompletions = lib.hm.dag.entryAfter order.after.shellCompletions ''
        mkdir -p ${stubbeDir}/src/zsh/fpaths.d
        ${pkgs.gh}/bin/gh completion -s zsh > ${stubbeDir}/src/zsh/fpaths.d/_gh 2>/dev/null
        ${pkgs.volta}/bin/volta completions zsh > ${stubbeDir}/src/zsh/fpaths.d/_volta 2>/dev/null
        ${pkgs.uv}/bin/uv generate-shell-completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_uv 2>/dev/null
      '';
    };
}
