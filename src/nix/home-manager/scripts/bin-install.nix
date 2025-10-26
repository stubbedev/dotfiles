{ config, pkgs, ... }:

''
  set -euo pipefail
  hdir="${config.home.homeDirectory}"
  lock_file="$hdir/.local/post-install.lock.json"

  read_lock_file() {
    if [ -f "$lock_file" ]; then
      cat "$lock_file"
    else
      echo "{}"
    fi
  }

  get_binary_version() {
    local binary_path="$1"
    local version=""
    if [ -x "$binary_path" ]; then
      case "$(basename "$binary_path")" in
        lua)
          version="$("$binary_path" -v 2>&1 | head -n1 | grep -o 'Lua [0-9.]*' | cut -d' ' -f2 || echo "")"
          ;;
        luajit)
          version="$("$binary_path" -v 2>&1 | head -n1 | grep -o 'LuaJIT [0-9.]*' | cut -d' ' -f2 || echo "")"
          ;;
        nvim)
          version="$("$binary_path" --version 2>&1 | head -n1 | grep -o 'NVIM v[0-9.]*' | cut -d'v' -f2 || echo "")"
          ;;
        *)
          version=""
          ;;
      esac
    fi
    echo "$version"
  }

  update_lock_file_entry() {
    local binary_path="$1"
    local version
    version="$(get_binary_version "$binary_path")"

    local lock_content
    lock_content="$(read_lock_file)"

    echo "$lock_content" | ${pkgs.jq}/bin/jq --arg path "$binary_path" --arg version "$version" '. + {($path): $version}' > "$lock_file"
  }

  check_version_mismatch() {
    local binary_path="$1"
    local current_version
    current_version="$(get_binary_version "$binary_path")"

    if [ -z "$current_version" ]; then
      return 0
    fi

    local lock_content
    lock_content="$(read_lock_file)"
    local expected_version
    expected_version="$(echo "$lock_content" | ${pkgs.jq}/bin/jq -r ".[\"$binary_path\"] // \"\"")"

    if [ -z "$expected_version" ] || [ "$current_version" != "$expected_version" ]; then
      return 0
    fi

    return 1
  }

  install_lua() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    echo "Downloading Lua 5.1.5..."
    curl -L https://www.lua.org/ftp/lua-5.1.5.tar.gz -o lua-5.1.5.tar.gz > /dev/null 2>&1
    echo "Extracting Lua 5.1.5..."
    tar -xzf lua-5.1.5.tar.gz > /dev/null 2>&1
    cd lua-5.1.5
    echo "Building Lua 5.1.5..."
    make generic -j"$(${pkgs.coreutils}/bin/nproc)" > /dev/null 2>&1
    echo "Installing Lua 5.1.5..."
    make install INSTALL_TOP="$hdir/.local" > /dev/null 2>&1
    echo "Lua 5.1 installed to $hdir/.local/bin"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "$hdir/.local/bin/lua"
  }

  install_luajit() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    echo "Cloning LuaJIT repository..."
    git clone https://luajit.org/git/luajit.git > /dev/null 2>&1
    cd luajit
    echo "Building LuaJIT..."
    make -j"$(${pkgs.coreutils}/bin/nproc)" > /dev/null 2>&1
    echo "Installing LuaJIT..."
    make install PREFIX="$hdir/.local" > /dev/null 2>&1
    rm -f "$hdir/.local/bin/luajit"
    mv "$hdir/.local/bin/luajit-"* "$hdir/.local/bin/luajit"
    echo "LuaJIT installed to $hdir/.local/bin"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "$hdir/.local/bin/luajit"
  }

  install_nvim() {
    local tmpdir latest_tag arch os nvim_archive tarball_url
    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    echo "Fetching latest Neovim release tag..."
    latest_tag="$(${pkgs.curl}/bin/curl -s https://api.github.com/repos/neovim/neovim/releases/latest | ${pkgs.jq}/bin/jq -r .tag_name)"
    echo "Using Neovim version: $latest_tag"
    arch="$(uname -m)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    if [ "$os" = "linux" ]; then
      if [ "$arch" = "x86_64" ]; then
        nvim_archive="nvim-linux-x86_64"
      elif [ "$arch" = "aarch64" ]; then
        nvim_archive="nvim-linux-arm64"
      else
        echo "Unsupported Linux architecture: $arch"
        exit 1
      fi
    elif [ "$os" = "darwin" ]; then
      if [ "$arch" = "x86_64" ]; then
        nvim_archive="nvim-macos-x86_64"
      elif [ "$arch" = "arm64" ]; then
        nvim_archive="nvim-macos-arm64"
      else
        echo "Unsupported macOS architecture: $arch"
        exit 1
      fi
    else
      echo "Unsupported operating system: $os"
      exit 1
    fi
    tarball_url="https://github.com/neovim/neovim/releases/download/$latest_tag/$nvim_archive.tar.gz"
    echo "Downloading Neovim tarball from: $tarball_url"
    ${pkgs.curl}/bin/curl -L "$tarball_url" -o "$nvim_archive.tar.gz" > /dev/null 2>&1
    if [ ! -f "$nvim_archive.tar.gz" ]; then
      echo "Failed to download Neovim tarball"
      exit 1
    fi
    echo "Extracting Neovim..."
    ${pkgs.gnutar}/bin/tar -xzf "$nvim_archive.tar.gz" > /dev/null 2>&1
    echo "Installing Neovim to $HOME/.local..."
    mkdir -p "$hdir/.local"
    cp -r "$nvim_archive"/* "$hdir/.local/"
    echo "Neovim installed to $hdir/.local/bin"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "$hdir/.local/bin/nvim"
  }

  echo "Installing gh-copilot extension..."
  "${pkgs.gh}/bin/gh" extension install github/gh-copilot > /dev/null 2>&1
  echo "Upgrading gh-copilot extension..."
  "${pkgs.gh}/bin/gh" extension upgrade github/gh-copilot > /dev/null 2>&1
  echo "Installing opencode-ai globally..."
  "${pkgs.bun}/bin/bun" install opencode-ai@latest --global > /dev/null 2>&1

  echo "Creating local bin directory..."
  mkdir -p "$hdir/.local/bin"

  # Set up build environment with Nix packages
  export PATH="${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gettext}/bin:${pkgs.libtool}/bin:${pkgs.autoconf}/bin:${pkgs.automake}/bin:${pkgs.jq}/bin:$hdir/.local/bin:$PATH"
  export CC="${pkgs.gcc}/bin/gcc"
  export CXX="${pkgs.gcc}/bin/g++"
  export CPPFLAGS="-I${pkgs.readline.dev}/include"
  export LDFLAGS="-L${pkgs.readline}/lib -L${pkgs.ncurses}/lib"

  if [ ! -x "$hdir/.local/bin/lua" ] || check_version_mismatch "$hdir/.local/bin/lua" ; then
    install_lua
  fi

  if [ ! -x "$hdir/.local/bin/luajit" ] || check_version_mismatch "$hdir/.local/bin/luajit" ; then
    install_luajit
  fi

  if [ ! -x "$hdir/.local/bin/nvim" ] || check_version_mismatch "$hdir/.local/bin/nvim" ; then
    install_nvim
  fi
''

