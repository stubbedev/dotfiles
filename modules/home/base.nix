_: {
  flake.modules.homeManager.base = { lib, ... }: {
    home = {
      username = lib.mkDefault "stubbe";
      # mkDefault so the HM-NixOS bridge can set this from
      # users.users.<name>.home without a priority conflict; on standalone
      # HM (non-NixOS) this default is the only definition.
      homeDirectory = lib.mkDefault "/home/stubbe";
      stateVersion = "26.05";
      # User-level PATH. Keep this minimal — every tool we use lands in
      # ~/.nix-profile/bin via Nix. Two exceptions:
      #   - ~/.config/composer/vendor/bin: PHP composer global packages.
      #   - ~/.local/share/pnpm:           pnpm global installs (PNPM_HOME).
      # Tool-managed dirs (~/.cargo/bin, ~/.bun/bin, ~/.go/bin, …) stay
      # off PATH so we don't shadow the Nix-pinned versions.
      sessionPath = [
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$HOME/.config/composer/vendor/bin"
        "$HOME/.local/share/pnpm"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/sbin"
      ];
    };
  };
}
