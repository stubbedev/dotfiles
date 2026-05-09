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
        ${pkgs.uv}/bin/uv generate-shell-completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_uv 2>/dev/null
        ${pkgs.lazygit}/bin/lazygit completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_lazygit 2>/dev/null
        ${lib.optionalString config.features.srv ''
          ${srvBin} completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_srv 2>/dev/null
        ''}
        ${lib.optionalString config.features.k8s ''
          ${pkgs.kubectl}/bin/kubectl completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_kubectl 2>/dev/null
          ${pkgs.minikube}/bin/minikube completion zsh > ${stubbeDir}/src/zsh/fpaths.d/_minikube 2>/dev/null
        ''}
        ${lib.optionalString config.features.php ''
          # FrankenPHP emits a Caddy-derived completion (it embeds Caddy);
          # rename caddy → frankenphp so the directives register against the
          # actual binary name. Internal function names get renamed too for
          # consistency with the file name (zsh autoloads _frankenphp).
          ${pkgs.frankenphp}/bin/frankenphp completion zsh 2>/dev/null \
            | sed 's/caddy/frankenphp/g' \
            > ${stubbeDir}/src/zsh/fpaths.d/_frankenphp
        ''}
      '';
    };
}
