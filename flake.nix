{
  description = "stubbedev dotfiles: home-manager (non-NixOS) + NixOS configurations + installer ISO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nix-community/nixGL#221: fixes the version regex for NVIDIA Open Kernel
    # Module 595.71.05+. Switch back to upstream once merged.
    nixgl = {
      url = "github:KeeTraxx/nixGL/fix-nvidia-kernel-param";
      # Imported via a path with `pkgs = final`, so its flake outputs are never
      # used and following ours just drops a redundant nixpkgs from the lock.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Hyprland and hy3 come from nixpkgs, not the official flake: nixpkgs builds
    # the plugin against the same compositor so they cannot drift, and patches
    # the `glaze 7...<8` CMake range the flake fails on.
    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Inputs that ship a binary cache do NOT follow our nixpkgs: their caches are
    # built against their own locked nixpkgs, and rebasing every derivation onto
    # ours means no store-path hash matches and everything builds from source.
    fenix.url = "github:nix-community/fenix";
    srv.url = "github:stubbedev/srv";
    treeman = {
      url = "github:stubbedev/treeman";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # what this one compiled. Pinned to the tag the SERVER runs (v1.0.0): the
    # cache-config API is versioned, so a client ahead of the server 404s
    # — tracking master means a client push can outrun the server's API;
    # keep the server current (see project_xilo_cache_server memory).
    xilo = {
      url = "github:stubbedev/xilo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jenkins-mcp = {
      url = "github:stubbedev/jenkins-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sentry-mcp = {
      url = "github:stubbedev/sentry-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atlassian-mcp = {
      url = "github:stubbedev/atlassian-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ds-mcp.url = "github:stubbedev/ds-mcp";
    html-to-md = {
      url = "github:stubbedev/html-to-md";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-mcp = {
      url = "github:stubbedev/nix-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cship = {
      url = "github:stephenleo/cship";
      flake = false;
    };
    proxy-mcp = {
      url = "github:stubbedev/proxy-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pty-mcp.url = "github:stubbedev/pty-mcp";
    notmuch-mcp.url = "github:stubbedev/notmuch-mcp";
    wayle = {
      # ?submodules=1: the github fetcher skips submodules, leaving the vendored
      # cava C sources missing.
      url = "git+https://github.com/stubbedev/wayle.git?ref=master&submodules=1";
    };
    # Pinned sources, so nothing clones at runtime.
    zsh-vim-mode = {
      url = "github:softmoth/zsh-vim-mode";
      flake = false;
    };
    zsh-fzf-artisan = {
      url = "github:stubbedev/zsh-fzf-artisan";
      flake = false;
    };
    zsh-fzf-npm-run = {
      url = "github:stubbedev/zsh-fzf-npm-run";
      flake = false;
    };
    # Release tag, bumped by `hm upgrade`.
    phpantom_lsp = {
      url = "github:PHPantom-dev/phpantom_lsp/0.10.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      # No build artifacts, so following ours just trims the lock.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Sources we build ourselves. `flake = false` means these are plain
    # checkouts, and the point of routing them through inputs is that their
    # revisions and hashes live in flake.lock -- nothing in-tree is pinned to a
    # commit hash, and `nix flake update` is the only way any of them move.
    # Where a URL carries a tag or version, that is deliberate: the version is
    # a decision, the hash is not.
    ghostscript-src = {
      url = "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10070/ghostscript-10.07.0.tar.xz";
      type = "tarball";
      flake = false;
    };
    imagemagick-src = {
      url = "github:ImageMagick/ImageMagick/7.1.2-25";
      flake = false;
    };
    libembroidery-src = {
      # No tagged release yet, so this tracks main.
      url = "github:Embroidermodder/libembroidery";
      flake = false;
    };
    tridactyl-theme-src = {
      url = "github:devnullvoid/tridactyl";
      flake = false;
    };

    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
