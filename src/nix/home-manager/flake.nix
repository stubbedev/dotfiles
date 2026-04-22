{
  description = "Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixgl.url = "github:nix-community/nixGL";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Use official Hyprland flake for better plugin compatibility.
    # Use v0.54.2 tag explicitly (refs/tags/…) so Nix does not look for a
    # non-existent branch named v0.54.2 when updating the flake input.
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.54.2&submodules=1";

    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      # Use hl0.54.2.1 tag (hyprland compatibility release). Point at tag ref to
      # avoid Nix searching for a branch named hl0.54.2.1.
      url = "github:outfoxxed/hy3?ref=refs/tags/hl0.54.2.1";
      inputs.hyprland.follows = "hyprland"; # Use the same hyprland as our main input
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Don't follow nixpkgs — fenix cache (nix-community.cachix.org) is built
    # against nixpkgs-unstable; following our nixpkgs causes cache misses.
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixpkgs-unstable ships 0.25.x but nvim-treesitter requires >= 0.26.1.
    # Track upstream master so nix flake update always pulls the latest.
    tree-sitter.url = "github:tree-sitter/tree-sitter";
    opencode.url = "github:anomalyco/opencode/d6fc5f414b1f78994fffd550d4104627dbbfac51";
    srv.url = "github:stubbedev/srv";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
