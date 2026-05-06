_: {
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      # Mirrors the font set installed via home.packages in
      # modules/packages/theming.nix. On NixOS these need to be system-wide
      # so the greeter (which runs before any user session) can render them.
      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        font-awesome
        adwaita-fonts
      ];

      fonts.fontconfig.enable = true;
    };
}
