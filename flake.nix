{
  description = "stubbedev dotfiles: NixOS + nix-on-droid configurations + installer ISO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Inputs that ship a binary cache do NOT follow our nixpkgs: their caches are
    # built against their own locked nixpkgs, and rebasing every derivation onto
    # ours means no store-path hash matches and everything builds from source.
    srv.url = "github:stubbedev/srv";
    treeman = {
      url = "github:stubbedev/treeman";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xilo = {
      url = "github:stubbedev/xilo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Crush fork: config-driven theming, git header, thinking toggle and
    # prompt height, so nothing has to be patched into the Go source here.
    harness = {
      url = "github:stubbedev/harness";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    shell-lsp = {
      url = "github:stubbedev/shell-lsp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    phix = {
      url = "github:stubbedev/phix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
    html-to-md = {
      url = "github:stubbedev/html-to-md";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cship = {
      url = "github:stephenleo/cship";
      flake = false;
    };
    claude-code = {
      # Tracks npm latest within ~1h of release; nixpkgs' claude-code lags.
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    notmuch-mcp = {
      url = "github:stubbedev/notmuch-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The whole lys desktop: compositor, shell, login, settings, polkit agent,
    # Secret Service, boot splash and power policy, from one flake.
    lys = {
      url = "github:stubbedev/lys";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-mesa.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        home-manager.follows = "home-manager";
      };
    };
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
    # Runs direnv in a background daemon so the prompt never waits on a
    # nix-direnv evaluation. Ships no binary cache.
    direnv-instant = {
      url = "github:Mic92/direnv-instant";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };
    libembroidery-src = {
      url = "github:Embroidermodder/libembroidery";
      flake = false;
    };
    tridactyl-theme-src = {
      url = "github:devnullvoid/tridactyl";
      flake = false;
    };
    # Prebuilt release binary. The version lives in this URL and is pinned by
    # flake.lock like every other input; the overlay consumes the tree
    # directly. Bump by hand: update the tag here, run `nix flake lock`.
    yayamlls = {
      url = "https://github.com/home-operations/yayamlls/releases/download/0.3.2/yayamlls_0.3.2_linux_amd64.tar.gz";
      type = "tarball";
      flake = false;
    };

    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Android host: nix-on-droid, the F-Droid app that runs a proot'd Nix
    # environment on Termux. master, not release-24.05: the release branch
    # pins a proot that cannot run glibc 2.42 (nixpkgs >= 26.05), master pins
    # one built for it. nixpkgs follows ours, so the phone shares the packages
    # and overlays of every other host.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
