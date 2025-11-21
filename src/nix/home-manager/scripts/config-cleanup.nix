{ config, pkgs, constants ? null, ... }:

let
  homeDir = config.home.homeDirectory;
  stubbeDir = if constants != null then
    constants.paths.dotfiles
  else
    "${homeDir}/.stubbe";
in ''
  rm -f ${homeDir}/.zcompdump > /dev/null 2>&1
  rm -rf "${homeDir}/.config/nvim"
  ln -sf "${stubbeDir}/src/nvim" "${homeDir}/.config/nvim"
  mkdir -p "${homeDir}/.tmux/plugins"
  if [ ! -d "${homeDir}/.tmux/plugins/tpm" ]; then
    ${pkgs.git}/bin/git clone --quiet https://github.com/tmux-plugins/tpm ${homeDir}/.tmux/plugins/tpm
  fi
  mkdir -p "${homeDir}/.config/lazygit"
  cat "${stubbeDir}/src/lazygit/state.yml" > "${homeDir}/.config/lazygit/state.yml"
  echo "lastversion: ${pkgs.lazygit.version}" >> "${homeDir}/.config/lazygit/state.yml"
  mkdir -p "${homeDir}/.config/btop"
  cat "${stubbeDir}/src/btop/btop.conf" > "${homeDir}/.config/btop/btop.conf"
  rm -rf "${homeDir}/.config/neomutt/accounts"
  ln -sf "${stubbeDir}/src/neomutt/accounts" "${homeDir}/.config/neomutt/accounts"
  rm -rf "${homeDir}/.config/aerc/accounts"
  ln -sf "${stubbeDir}/src/aerc/accounts" "${homeDir}/.config/aerc/accounts"
''

