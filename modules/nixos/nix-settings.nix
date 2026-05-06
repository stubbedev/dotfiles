{ config, ... }:
{
  flake.modules.nixos.nixSettings =
    { ... }:
    {
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Mirror the HM-bridge config so environment.systemPackages and any
      # NixOS-side `pkgs.*` reference resolve through the same overlays
      # (nixgl, cship, opencode) the HM build sees. Without this, system
      # packages fall back to a vanilla nixpkgs eval and miss the overrides.
      nixpkgs.config = {
        allowUnfree = true;
        allowInsecure = true;
      };

      nixpkgs.overlays = builtins.attrValues config.flake.overlays;
    };
}
