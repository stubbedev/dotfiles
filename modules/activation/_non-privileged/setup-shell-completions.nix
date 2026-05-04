{ inputs, ... }:
let
  inherit (inputs) srv;
in
{
  args =
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
      inherit (pkgs.stdenv.hostPlatform) system;
      srvBin = "${srv.packages.${system}.srv}/bin/srv";
    in
    {
      actionScript = ''
        mkdir -p ${stubbeDir}/src/zsh/fpaths.d
        ${pkgs.gh}/bin/gh completion -s zsh > ${stubbeDir}/src/zsh/fpaths.d/_gh 2>/dev/null
        ${pkgs.volta}/bin/volta completions zsh > ${stubbeDir}/src/zsh/fpaths.d/_volta 2>/dev/null
        ${pkgs.uv}/bin/uv generate-shell-completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_uv 2>/dev/null
        ${lib.optionalString config.features.srv ''
          ${srvBin} completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_srv 2>/dev/null
        ''}
        ${lib.optionalString config.features.k8s ''
          ${pkgs.kubectl}/bin/kubectl completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_kubectl 2>/dev/null
          ${pkgs.minikube}/bin/minikube completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_minikube 2>/dev/null
        ''}
      '';
    };
}
