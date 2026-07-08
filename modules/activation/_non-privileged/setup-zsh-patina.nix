# Generates the zsh-patina shell hook at switch time. `zsh-patina
# activate` is impure (starts/version-syncs the daemon, embeds
# $XDG_RUNTIME_DIR) so it can't be a nix build product, but running it
# per shell would cost a fork — so it runs once per switch and shells
# source the zcompiled result (see modules/home/zsh/zsh.nix). The daemon
# itself is owned by the zsh-patina systemd user service
# (modules/home/zsh/patina.nix).
_: {
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, pkgs, ... }:
    {
      actionScript = ''
        # activate embeds $XDG_RUNTIME_DIR/zsh-patina as the socket path;
        # NixOS runs user activation without XDG_RUNTIME_DIR, so fall back
        # to the same path login shells get.
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        _patina_cache='${config.xdg.cacheHome}/zsh'
        mkdir -p "$_patina_cache"
        if ${pkgs.zsh-patina}/bin/zsh-patina activate > "$_patina_cache/patina-init.zsh.tmp" 2>/dev/null; then
          mv "$_patina_cache/patina-init.zsh.tmp" "$_patina_cache/patina-init.zsh"
          ${pkgs.zsh}/bin/zsh -c 'zcompile "$1"' _ "$_patina_cache/patina-init.zsh" || true
        else
          # Keep a previous good script if activate fails (e.g. no runtime
          # dir in a container build); shells degrade to no highlighting.
          rm -f "$_patina_cache/patina-init.zsh.tmp"
        fi
        unset _patina_cache
      '';
    };
}
