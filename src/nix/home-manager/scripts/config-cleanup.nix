{ config, pkgs, constants ? null, ... }:

let
  homeDir = config.home.homeDirectory;
  stubbeDir = if constants != null then
    constants.paths.dotfiles
  else
    "${homeDir}/.stubbe";
in ''
  rm -f ${homeDir}/.zcompdump > /dev/null 2>&1

  # NEOVIM Setup
  rm -rf "${homeDir}/.config/nvim"
  ln -sf "${stubbeDir}/src/nvim" "${homeDir}/.config/nvim"

  # TMUX Plugin Manager Setup
  mkdir -p "${homeDir}/.tmux/plugins"
  if [ ! -d "${homeDir}/.tmux/plugins/tpm" ]; then
    ${pkgs.git}/bin/git clone --quiet https://github.com/tmux-plugins/tpm ${homeDir}/.tmux/plugins/tpm
  fi

  # LAZYGIT Setup
  mkdir -p "${homeDir}/.config/lazygit"
  cat "${stubbeDir}/src/lazygit/state.yml" > "${homeDir}/.config/lazygit/state.yml"
  echo "lastversion: ${pkgs.lazygit.version}" >> "${homeDir}/.config/lazygit/state.yml"

  # BTOP Setup
  mkdir -p "${homeDir}/.config/btop"
  cat "${stubbeDir}/src/btop/btop.conf" > "${homeDir}/.config/btop/btop.conf"

  # NEOMUTT Setup
  rm -rf "${homeDir}/.config/neomutt/accounts"
  ln -sf "${stubbeDir}/src/neomutt/accounts" "${homeDir}/.config/neomutt/accounts"

  # AERC Setup
  mkdir -p "${homeDir}/.config/aerc"
  rm -rf "${homeDir}/.config/aerc/stylesets"
  ln -s "${stubbeDir}/src/aerc/stylesets" "${homeDir}/.config/aerc/stylesets"
  rm -rf "${homeDir}/.config/aerc/accounts"
  ln -s "${stubbeDir}/src/aerc/accounts" "${homeDir}/.config/aerc/accounts"
  rm -rf "${homeDir}/.config/aerc/accounts.conf"
  ln -s "${stubbeDir}/src/aerc/accounts.conf" "${homeDir}/.config/aerc/accounts.conf"
  chmod 600 "${stubbeDir}/src/aerc/accounts.conf"
''

