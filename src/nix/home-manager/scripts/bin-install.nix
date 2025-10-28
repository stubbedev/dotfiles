{ config, pkgs, constants, ... }:

''
  set -euo pipefail
  hdir="${config.home.homeDirectory}"

  read_lock_file() {
    if [ -f "${constants.paths.customBinLock}" ]; then
      cat "${constants.paths.customBinLock}"
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

    echo "$lock_content" | ${pkgs.jq}/bin/jq --arg path "$binary_path" --arg version "$version" '. + {($path): $version}' > "${constants.paths.customBinLock}"
  }

  safe_replace_binary() {
    local source_path="$1"
    local target_path="$2"
    local temp_path="$target_path.tmp.$$"

    # Copy to temporary file first
    cp "$source_path" "$temp_path"
    chmod +x "$temp_path"

    # Atomic move - this works even if the target is busy
    mv "$temp_path" "$target_path"
  }

  safe_install_to_local() {
    local source_dir="$1"
    local target_dir="$2"

    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"

    # Copy files, replacing binaries safely
    find "$source_dir" -type f -executable | while read -r source_file; do
      local relative_path="''${source_file#$source_dir/}"
      local target_file="$target_dir/$relative_path"
      local target_parent="$(dirname "$target_file")"

      mkdir -p "$target_parent"
      safe_replace_binary "$source_file" "$target_file"
    done

    # Copy non-executable files normally
    find "$source_dir" -type f ! -executable | while read -r source_file; do
      local relative_path="''${source_file#$source_dir/}"
      local target_file="$target_dir/$relative_path"
      local target_parent="$(dirname "$target_file")"

      mkdir -p "$target_parent"
      cp "$source_file" "$target_file"
    done

    # Copy directories
    find "$source_dir" -type d | while read -r source_dir_path; do
      local relative_path="''${source_dir_path#$source_dir/}"
      [ -n "$relative_path" ] && mkdir -p "$target_dir/$relative_path"
    done
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
    local install_tmp="$(mktemp -d)"
    make install INSTALL_TOP="$install_tmp" > /dev/null 2>&1
    safe_install_to_local "$install_tmp" "$hdir/.local"
    rm -rf "$install_tmp"
    echo "Lua 5.1 installed to ${constants.paths.customBinDir}"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "${constants.paths.customBinDir}/lua"
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
    local install_tmp="$(mktemp -d)"
    make install PREFIX="$install_tmp" > /dev/null 2>&1
    # Rename the versioned luajit binary to just luajit
    if ls "$install_tmp/bin/luajit-"* > /dev/null 2>&1; then
      mv "$install_tmp/bin/luajit-"* "$install_tmp/bin/luajit"
    fi
    safe_install_to_local "$install_tmp" "$hdir/.local"
    rm -rf "$install_tmp"
    echo "LuaJIT installed to ${constants.paths.customBinDir}"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "${constants.paths.customBinDir}/luajit"
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
    safe_install_to_local "$nvim_archive" "$hdir/.local"
    echo "Neovim installed to ${constants.paths.customBinDir}"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "${constants.paths.customBinDir}/nvim"
  }

  echo "Installing gh-copilot extension..."
  "${pkgs.gh}/bin/gh" extension install github/gh-copilot > /dev/null 2>&1
  echo "Upgrading gh-copilot extension..."
  "${pkgs.gh}/bin/gh" extension upgrade github/gh-copilot > /dev/null 2>&1
  echo "Installing opencode-ai globally..."
  "${pkgs.bun}/bin/bun" install opencode-ai@latest --global > /dev/null 2>&1

  echo "Creating local bin directory..."
  mkdir -p "${constants.paths.customBinDir}"

  # Set up build environment with Nix packages
  export PATH="${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gettext}/bin:${pkgs.libtool}/bin:${pkgs.autoconf}/bin:${pkgs.automake}/bin:${pkgs.jq}/bin:${constants.paths.customBinDir}:$PATH"
  export CC="${pkgs.gcc}/bin/gcc"
  export CXX="${pkgs.gcc}/bin/g++"
  export CPPFLAGS="-I${pkgs.readline.dev}/include"
  export LDFLAGS="-L${pkgs.readline}/lib -L${pkgs.ncurses}/lib"

  if [ ! -x "${constants.paths.customBinDir}/lua" ] || check_version_mismatch "${constants.paths.customBinDir}/lua" ; then
    install_lua
  fi

  if [ ! -x "${constants.paths.customBinDir}/luajit" ] || check_version_mismatch "${constants.paths.customBinDir}/luajit" ; then
    install_luajit
  fi

  if [ ! -x "${constants.paths.customBinDir}/nvim" ] || check_version_mismatch "${constants.paths.customBinDir}/nvim" ; then
    install_nvim
  fi
''

