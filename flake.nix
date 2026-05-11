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
    # Use tag ref explicitly (refs/tags/…) so Nix does not look for a
    # non-existent branch named the version string when updating the flake input.
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.54.3&submodules=1";

    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      # hl0.54.2.1 is the latest release; no hl0.54.3 tag yet.
      # Follows our hyprland input so it builds against v0.54.3.
      url = "github:outfoxxed/hy3?ref=refs/tags/hl0.54.2.1";
      inputs.hyprland.follows = "hyprland";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Don't follow nixpkgs — fenix cache (nix-community.cachix.org) is built
    # against nixpkgs-unstable; following our nixpkgs causes cache misses.
    fenix.url = "github:nix-community/fenix";
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
    # Signed bootloader for UEFI Secure Boot. Activated only when
    # host.secureBoot = true; see modules/nixos/lanzaboote.nix.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative bind-mounts + tmpfs root for stateless systems.
    # Activated only when host.impermanent = true; see
    # modules/nixos/impermanence.nix.
    impermanence.url = "github:nix-community/impermanence";
    # Wraps Neovim with a lua config dir + nixpkgs-supplied LSPs/tools.
    # Lua tree lives at src/nvim/, symlinked into ~/.config/nvim by
    # modules/activation/_non-privileged/setup-nvim.nix; lazy.nvim handles
    # plugin downloads from GitHub at runtime.
    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
