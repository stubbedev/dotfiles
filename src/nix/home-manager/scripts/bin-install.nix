{ config, pkgs, ... }:

''
  ${pkgs.gh}/bin/gh extension install github/gh-copilot > /dev/null 2>&1
  ${pkgs.gh}/bin/gh extension upgrade github/gh-copilot > /dev/null 2>&1
  ${pkgs.bun}/bin/bun install opencode-ai@latest --global > /dev/null 2>&1

  mkdir -p $HOME/.local/bin

  # Set up build environment with Nix packages
  export PATH="${pkgs.gcc}/bin:${pkgs.gnumake}/bin:${pkgs.git}/bin:${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:$PATH"
  export CC="${pkgs.gcc}/bin/gcc"
  export CXX="${pkgs.gcc}/bin/g++"

  # Install LuaJIT from source
  if ! command -v luajit &> /dev/null || ! $HOME/.local/bin/luajit -v &> /dev/null; then
    echo "Installing LuaJIT from source..."
    cd /tmp
    if [ -d "luajit" ]; then
      rm -rf luajit
    fi
    git clone https://luajit.org/git/luajit.git > /dev/null 2>&1
    cd luajit
    make -j$(${pkgs.coreutils}/bin/nproc) > /dev/null 2>&1
    make install PREFIX=$HOME/.local > /dev/null 2>&1
    cd ..
    rm -rf luajit
    echo "LuaJIT installed to $HOME/.local/bin"
  fi

  # Install Lua 5.1 from source
  if ! command -v lua5.1 &> /dev/null || ! $HOME/.local/bin/lua -v 2>&1 | grep -q "5.1" ; then
    echo "Installing Lua 5.1 from source..."
    cd /tmp
    if [ -f "lua-5.1.5.tar.gz" ]; then
      rm -f lua-5.1.5.tar.gz
    fi
    if [ -d "lua-5.1.5" ]; then
      rm -rf lua-5.1.5
    fi
    curl -L https://www.lua.org/ftp/lua-5.1.5.tar.gz -o lua-5.1.5.tar.gz > /dev/null 2>&1
    tar -xzf lua-5.1.5.tar.gz > /dev/null 2>&1
    cd lua-5.1.5
    make linux -j$(${pkgs.coreutils}/bin/nproc) > /dev/null 2>&1
    make install INSTALL_TOP=$HOME/.local > /dev/null 2>&1
    cd ..
    rm -rf lua-5.1.5 lua-5.1.5.tar.gz
    echo "Lua 5.1 installed to $HOME/.local/bin"
  fi
''

