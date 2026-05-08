_: {
  flake.modules.nixos.greetd =
    { pkgs, lib, ... }:
    {
      services.greetd.enable = lib.mkForce false;

      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        theme = "catppuccin-mocha-mauve";
        extraPackages = [
          pkgs.catppuccin-sddm
          pkgs.vimix-cursors
        ];
        settings = {
          Theme = {
            CursorTheme = "Vimix-cursors";
            CursorSize = 24;
          };
        };
      };

      # SDDM's ThemeDir is /run/current-system/sw/share/sddm/themes, populated
      # via environment.pathsToLink. extraPackages only widens SDDM's PATH —
      # it does not contribute to that themes directory. systemPackages does.
      environment.systemPackages = [ pkgs.catppuccin-sddm ];
    };
}
