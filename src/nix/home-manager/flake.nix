{
  description = "Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixgl.url = "github:nix-community/nixGL";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Use official Hyprland flake for better plugin compatibility.
    # Use v0.53.0 tag explicitly (refs/tags/…) so Nix does not look for a
    # non-existent branch named v0.53.0 when updating the flake input.
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.53.0&submodules=1";

    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      # Use hl0.53.0 tag (hyprland compatibility release). Point at tag ref to
      # avoid Nix searching for a branch named hl0.53.0.
      url = "github:outfoxxed/hy3?ref=refs/tags/hl0.53.0";
      inputs.hyprland.follows = "hyprland"; # Use the same hyprland as our main input
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
