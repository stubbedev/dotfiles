{ config, pkgs, constants, ... }:

''
  set -euo pipefail
  hdir="${config.home.homeDirectory}"
  
  # Set redirect suffix based on debug flag
  if [ -n "''${BIN_INSTALL_DEBUG:-}" ]; then
    # Debug mode: don't redirect
    REDIRECT_SUFFIX=""
  else
    # Normal mode: redirect to /dev/null
    REDIRECT_SUFFIX="> /dev/null 2>&1"
  fi

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
        alacritty)
          version="$("$binary_path" --version 2>&1 | head -n1 | grep -o 'alacritty [0-9.]*' | cut -d' ' -f2 || echo "")"
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
    eval "curl -L https://www.lua.org/ftp/lua-5.1.5.tar.gz -o lua-5.1.5.tar.gz $REDIRECT_SUFFIX"
    echo "Extracting Lua 5.1.5..."
    eval "tar -xzf lua-5.1.5.tar.gz $REDIRECT_SUFFIX"
    cd lua-5.1.5
    echo "Building Lua 5.1.5..."
    eval "make generic -j\"\$(${pkgs.coreutils}/bin/nproc)\" $REDIRECT_SUFFIX"
    echo "Installing Lua 5.1.5..."
    local install_tmp="$(mktemp -d)"
    eval "make install INSTALL_TOP=\"$install_tmp\" $REDIRECT_SUFFIX"
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
    eval "git clone https://luajit.org/git/luajit.git $REDIRECT_SUFFIX"
    cd luajit
    echo "Building LuaJIT..."
    eval "make -j\"\$(${pkgs.coreutils}/bin/nproc)\" $REDIRECT_SUFFIX"
    echo "Installing LuaJIT..."
    local install_tmp="$(mktemp -d)"
    eval "make install PREFIX=\"$install_tmp\" $REDIRECT_SUFFIX"
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
    eval "${pkgs.curl}/bin/curl -L \"$tarball_url\" -o \"$nvim_archive.tar.gz\" $REDIRECT_SUFFIX"
    if [ ! -f "$nvim_archive.tar.gz" ]; then
      echo "Failed to download Neovim tarball"
      exit 1
    fi
    echo "Extracting Neovim..."
    eval "${pkgs.gnutar}/bin/tar -xzf \"$nvim_archive.tar.gz\" $REDIRECT_SUFFIX"
    echo "Installing Neovim to $HOME/.local..."
    safe_install_to_local "$nvim_archive" "$hdir/.local"
    echo "Neovim installed to ${constants.paths.customBinDir}"
    cd
    rm -rf "$tmpdir"
    update_lock_file_entry "${constants.paths.customBinDir}/nvim"
  }

  install_alacritty() {
    local real_binary="$hdir/.local/libexec/alacritty"
    local cargo_binary="$hdir/.local/bin/alacritty"
    local wrapper_path="${constants.paths.customBinDir}/alacritty"
    
    # Check if we need to install/update the binary
    local need_install=false
    if [ ! -f "$real_binary" ]; then
      # Real binary doesn't exist, check if cargo binary exists
      if [ -f "$cargo_binary" ]; then
        # Check if it's the actual ELF binary (not a wrapper)
        if file "$cargo_binary" 2>/dev/null | grep -q "ELF"; then
          need_install=true
        fi
      else
        # Need to install from cargo
        echo "Installing Alacritty using cargo..."
        eval "\"${config.home.homeDirectory}/.cargo/bin/cargo\" install alacritty --root \"$hdir/.local\" $REDIRECT_SUFFIX"
        need_install=true
      fi
    fi
    
    # Move cargo binary to libexec if it exists and is an ELF binary
    if [ -f "$cargo_binary" ] && [ ! -L "$cargo_binary" ]; then
      if file "$cargo_binary" 2>/dev/null | grep -q "ELF"; then
        mkdir -p "$(dirname "$real_binary")"
        mv "$cargo_binary" "$real_binary"
      fi
    fi
    
    # Verify the real binary exists
    if [ ! -f "$real_binary" ]; then
      echo "Warning: Alacritty binary not found at $real_binary"
      return
    fi
    
    # Always create/update the wrapper script
    {
      echo "#!/usr/bin/env bash"
      echo "# Wrapper for Alacritty to load Nix libraries"
      echo "export LD_LIBRARY_PATH=\"${pkgs.freetype}/lib:${pkgs.fontconfig}/lib:${pkgs.xorg.libxcb}/lib:${pkgs.libxkbcommon}/lib''${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH\""
      echo "exec \"$real_binary\" \"\$@\""
    } > "$wrapper_path"
    chmod +x "$wrapper_path"
    
    echo "Alacritty installed to ${constants.paths.customBinDir}"
    update_lock_file_entry "${constants.paths.customBinDir}/alacritty"
  }

  # Set up build environment with Nix packages
  export PATH="${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gettext}/bin:${pkgs.libtool}/bin:${pkgs.autoconf}/bin:${pkgs.automake}/bin:${pkgs.jq}/bin:${pkgs.python3}/bin:${pkgs.scdoc}/bin:${constants.paths.customBinDir}:${config.home.homeDirectory}/.cargo/bin:$PATH"
  export CC="${pkgs.gcc}/bin/gcc"
  export CXX="${pkgs.gcc}/bin/g++"
  export CPPFLAGS="-I${pkgs.readline.dev}/include -I${pkgs.freetype.dev}/include/freetype2 -I${pkgs.fontconfig.dev}/include -I${pkgs.xorg.libxcb.dev}/include -I${pkgs.libxkbcommon.dev}/include"
  export LDFLAGS="-L${pkgs.readline}/lib -L${pkgs.ncurses}/lib -L${pkgs.freetype}/lib -L${pkgs.fontconfig}/lib -L${pkgs.xorg.libxcb}/lib -L${pkgs.libxkbcommon}/lib"
  OLD_PKG_CONFIG_PATH="''${PKG_CONFIG_PATH:-}"
  PKG_CONFIG_PATH="${pkgs.freetype.dev}/lib/pkgconfig:${pkgs.fontconfig.dev}/lib/pkgconfig:${pkgs.xorg.libxcb.dev}/lib/pkgconfig:${pkgs.libxkbcommon.dev}/lib/pkgconfig"
  [ -n "$OLD_PKG_CONFIG_PATH" ] && PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$OLD_PKG_CONFIG_PATH"
  export PKG_CONFIG_PATH

  if [ ! -x "${config.home.homeDirectory}/.cargo/bin/cargo" ]; then
    echo "Installing rustup toolchain..."
    "${pkgs.curl}/bin/curl" --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  fi

  echo "Installing opencode-ai globally..."
  eval "\"${pkgs.bun}/bin/bun\" install opencode-ai@latest --global $REDIRECT_SUFFIX"

  echo "Creating local bin directory..."
  mkdir -p "${constants.paths.customBinDir}"


  if [ ! -x "${constants.paths.customBinDir}/lua" ] || check_version_mismatch "${constants.paths.customBinDir}/lua" ; then
    install_lua
  fi

  if [ ! -x "${constants.paths.customBinDir}/luajit" ] || check_version_mismatch "${constants.paths.customBinDir}/luajit" ; then
    install_luajit
  fi

  if [ ! -x "${constants.paths.customBinDir}/nvim" ] || check_version_mismatch "${constants.paths.customBinDir}/nvim" ; then
    install_nvim
  fi

  if [ -x "${config.home.homeDirectory}/.cargo/bin/cargo" ]; then
    # Check if binary exists in either location or if version changed
    local real_binary="${config.home.homeDirectory}/.local/libexec/alacritty"
    local cargo_binary="${config.home.homeDirectory}/.local/bin/alacritty"
    if [ ! -x "${constants.paths.customBinDir}/alacritty" ] || \
       [ ! -f "$real_binary" ] || \
       ([ -f "$cargo_binary" ] && file "$cargo_binary" 2>/dev/null | grep -q "ELF") || \
       check_version_mismatch "${constants.paths.customBinDir}/alacritty" ; then
      install_alacritty
    fi
  fi
''

