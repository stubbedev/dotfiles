{
  description = "stubbedev dotfiles: home-manager (non-NixOS) + NixOS configurations + installer ISO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Pinned to KeeTraxx PR #221 (https://github.com/nix-community/nixGL/pull/221)
    # Drops `kernel = null` override removed from nixpkgs nvidia-x11/generic.nix
    # and fixes version regex for NVIDIA Open Kernel Module 595.71.05+
    # Switch back to github:nix-community/nixGL once #221 is merged
    nixgl.url = "github:KeeTraxx/nixGL/fix-nvidia-kernel-param";
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
    opencode.url = "github:anomalyco/opencode/ac6aa43e";
    srv.url = "github:stubbedev/srv";
    cship = {
      url = "github:stephenleo/cship";
      flake = false;
    };
    # Used by the installer ISO build for partitioning declaration.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets management. Encrypted secrets live under secrets/, keyed to
    # per-machine age recipients in .sops.yaml. Decrypted at HM activation.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
