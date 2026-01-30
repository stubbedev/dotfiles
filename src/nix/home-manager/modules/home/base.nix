{ ... }:
{
  flake.modules.homeManager.base = { constants, ... }: {
    home = {
      username = constants.user.name;
      homeDirectory = "/home/${constants.user.name}";
      stateVersion = "25.11";
      sessionPath = [
        "$HOME/.cargo/bin"
        "$HOME/.bun/bin"
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$HOME/.local/share/flatpak/exports/bin"
        "/var/lib/flatpak/exports/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ];
    };
  };
}
