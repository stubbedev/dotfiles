{ config, pkgs, constants ? null, ... }:

let
  homeDir = config.home.homeDirectory;
  stubbeDir = if constants != null then
    constants.paths.dotfiles
  else
    "${homeDir}/.stubbe";
in ''
  ${pkgs.gh}/bin/gh completion -s zsh > ${stubbeDir}/src/zsh/fpaths.d/_gh
  ${pkgs.volta}/bin/volta completions zsh > ${stubbeDir}/src/zsh/fpaths.d/_volta
  ${pkgs.uv}/bin/uv generate-shell-completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_uv
''

