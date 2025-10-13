{ config, pkgs, ... }:

''
  echo "Installing gh-copilot extension..."
  ${pkgs.gh}/bin/gh extension install github/gh-copilot > /dev/null 2>&1
  echo "Upgrading gh-copilot extension..."
  ${pkgs.gh}/bin/gh extension upgrade github/gh-copilot > /dev/null 2>&1
  echo "Installing opencode-ai globally..."
  ${pkgs.bun}/bin/bun install opencode-ai@latest --global > /dev/null 2>&1

  echo "Creating local bin directory..."
  mkdir -p $HOME/.local/bin

  # Set up build environment with Nix packages
  export PATH="${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:${pkgs.cmake}/bin:${pkgs.pkg-config}/bin:${pkgs.gettext}/bin:${pkgs.libtool}/bin:${pkgs.autoconf}/bin:${pkgs.automake}/bin:$PATH"
  export CC="${pkgs.gcc}/bin/gcc"
  export CXX="${pkgs.gcc}/bin/g++"
  export CPPFLAGS="-I${pkgs.readline.dev}/include"
  export LDFLAGS="-L${pkgs.readline}/lib -L${pkgs.ncurses}/lib"

  if ! command -v lua5.1 &> /dev/null || ! $HOME/.local/bin/lua -v 2>&1 | grep -q "5.1" ; then
    echo "Installing Lua 5.1 from source..."
    cd /tmp
    if [ -f "lua-5.1.5.tar.gz" ]; then
      rm -f lua-5.1.5.tar.gz
    fi
    if [ -d "lua-5.1.5" ]; then
      rm -rf lua-5.1.5
    fi
    echo "Downloading Lua 5.1.5..."
    curl -L https://www.lua.org/ftp/lua-5.1.5.tar.gz -o lua-5.1.5.tar.gz > /dev/null 2>&1
    echo "Extracting Lua 5.1.5..."
    tar -xzf lua-5.1.5.tar.gz > /dev/null 2>&1
    cd lua-5.1.5
    echo "Building Lua 5.1.5..."
    make generic -j$(${pkgs.coreutils}/bin/nproc) > /dev/null 2>&1
    echo "Installing Lua 5.1.5..."
    make install INSTALL_TOP=$HOME/.local > /dev/null 2>&1
    cd ..
    rm -rf lua-5.1.5 lua-5.1.5.tar.gz
    echo "Lua 5.1 installed to $HOME/.local/bin"
  fi

  if ! command -v luajit &> /dev/null || ! $HOME/.local/bin/luajit -v &> /dev/null; then
    echo "Installing LuaJIT from source..."
    cd /tmp
    if [ -d "luajit" ]; then
      rm -rf luajit
    fi
    echo "Cloning LuaJIT repository..."
    git clone https://luajit.org/git/luajit.git > /dev/null 2>&1
    cd luajit
    echo "Building LuaJIT..."
    make -j$(${pkgs.coreutils}/bin/nproc) > /dev/null 2>&1
    echo "Installing LuaJIT..."
    make install PREFIX=$HOME/.local > /dev/null 2>&1
    # Remove symlink and rename binary directly to luajit
    rm -f $HOME/.local/bin/luajit
    mv $HOME/.local/bin/luajit-* $HOME/.local/bin/luajit
    cd ..
    rm -rf luajit
    echo "LuaJIT installed to $HOME/.local/bin"
  fi

  if ! command -v nvim &> /dev/null || ! $HOME/.local/bin/nvim --version &> /dev/null; then
    echo "Installing Neovim from source..."
    cd /tmp
    if [ -d "neovim" ]; then
      rm -rf neovim
    fi
    echo "Cloning Neovim repository..."
    git clone --depth 1 https://github.com/neovim/neovim.git > /dev/null 2>&1
    cd neovim
    echo "Building Neovim..."
    make CMAKE_BUILD_TYPE=RelWithDebInfo -j$(${pkgs.coreutils}/bin/nproc) > /dev/null 2>&1
    echo "Installing Neovim..."
    make CMAKE_INSTALL_PREFIX=$HOME/.local install > /dev/null 2>&1
    cd ..
    rm -rf neovim
    echo "Neovim installed to $HOME/.local/bin"
  fi
''

